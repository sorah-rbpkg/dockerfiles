local common_steps = [
  {
    run: |||
      mkdir -p ~/.docker\n
      echo '{"experimental": "enabled"}' > ~/.docker/config.json
    |||,
  },
  {
    uses: 'ruby/setup-ruby@v1',
    with: { 'ruby-version': '3.3' },
  },
  {
    name: 'login-dockerhub',
    run: 'echo ${{ secrets.DOCKERHUB_TOKEN }} | docker login -u sorah --password-stdin',
  },
  {
    name: 'login-ghcr',
    run: 'echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin',
  },
  {
    uses: 'aws-actions/configure-aws-credentials@v1',
    with: {
      'aws-region': 'us-east-1',
      'role-to-assume': '${{ secrets.AWS_ROLE_TO_ASSUME }}',
      'role-duration-seconds': 14400,
      'role-skip-session-tagging': 'true',
    },
  },
  // FIXME: https://github.com/aws-actions/amazon-ecr-login/issues/116
  {
    name: 'Login to ECR Public',
    run: 'aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws',
  },
  { uses: 'actions/checkout@v3' },
];

local permissions = {
  'id-token': 'write',
  contents: 'read',
  packages: 'write',
};

local splitWithSpace = function(s) [token for token in std.split(s, ' ') if token != ''];
local matrix = [
  // NOTE: also update config.rb when adding new distro
  { series: '3.0', distro: splitWithSpace('focal jammy                                   '), arm: true },
  { series: '3.1', distro: splitWithSpace('focal jammy                                   '), arm: true },
  { series: '3.2', distro: splitWithSpace('focal jammy noble              bookworm       '), arm: true },
  { series: '3.3', distro: splitWithSpace('focal jammy noble              bookworm trixie'), arm: true },
  { series: '3.4', distro: splitWithSpace('      jammy noble resolute     bookworm trixie'), arm: true },
  { series: '4.0', distro: splitWithSpace('      jammy noble resolute     bookworm trixie'), arm: true },
  { series: '4.1', distro: splitWithSpace('            noble resolute              trixie'), arm: true },
];
local archs = ['amd64', 'arm64'];
// Series sorah-rbpkg/build's nightly.yml builds packages of.
local nightly_series = ['3.3', '3.4', '4.0'];

local build_job_patterns = [
  { series: series_and_distro.series, distro: distro, arch: arch }
  for series_and_distro in matrix
  for distro in series_and_distro.distro
  for arch in archs
  if arch == 'amd64' || (arch == 'arm64' && series_and_distro.series != '2.6')
];

local manifest_subtag_job_patterns = [
  { series: series_and_distro.series, distro: distro }
  for series_and_distro in matrix
  for distro in series_and_distro.distro
];

local pattern_to_job_name(prefix, pattern) =
  std.format('%s-%s-%s', [prefix, std.strReplace(pattern.series, '.', 'x'), pattern.distro]) +
  (if std.objectHas(pattern, 'arch') then std.format('-%s', [pattern.arch]) else '');


// The packages of sorah-rbpkg/build's nightly.yml are artifacts there, which only its own token can download.
local nightly_fetch_steps(pattern) = [
  {
    id: 'nightly-token',
    uses: 'sorah/sts-cat/.github/actions/exchange-token@19e1177084d0f2dedb575ab1b78bd2a1a100f6e9',  // main
    with: {
      endpoint: '${{ secrets.STS_CAT_ENDPOINT }}',
      scope: 'sorah-rbpkg',
      identity: 'dockerfiles-nightly',
      audience: 'https://sts-cat.nkmi.me',
    },
  },
  {
    run: 'ruby fetch-nightly.rb',
    env: {
      GH_TOKEN: '${{ steps.nightly-token.outputs.token }}',
      SERIES_FILTER: pattern.series,
      DIST_FILTER: pattern.distro,
      ARCH_FILTER: pattern.arch,
    },
  },
];

local build_job(pattern, nightly=false) =
  local name = pattern_to_job_name(if nightly then 'build-nightly' else 'build', pattern);
  local target = std.format('%s%s-%s', [if nightly then 'nightly-' else '', pattern.series, pattern.distro]);
  {
    _name:: name,
    [name]: {
      name: name,
      needs: ['plan'],
      'if': std.format("needs.plan.outputs.all == 'true' || contains(fromJSON(needs.plan.outputs.targets), '%s')", [target]),
      'runs-on': (if pattern.arch == 'arm64' then 'ubuntu-24.04-arm' else 'ubuntu-24.04'),
      permissions: permissions,
      steps: common_steps + (if nightly then nightly_fetch_steps(pattern) else []) + [
        // The docker driver cannot push provenance and SBOM attestations.
        { uses: 'docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069' },  // v4.4.1
        {
          run: 'ruby build.rb --pull --push' + (if nightly then ' --nightly' else ''),
          env: {
            SERIES_FILTER: pattern.series,
            DIST_FILTER: pattern.distro,
            ARCH_FILTER: pattern.arch,
          },
        },
        {
          uses: 'actions/upload-artifact@v4',
          with: {
            name: name + '-artifacts',
            path: 'tmp/built_images.json',
            'retention-days': 1,
          },
        },
      ],
    },
  };


local attest_step(kind) = {
  uses: 'actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6',  // v4.2.2
  'if': std.format('steps.manifest.outputs.%s', [kind]),
  with: {
    'subject-name': '${{ steps.manifest.outputs.name }}',
    'subject-digest': std.format('${{ steps.manifest.outputs.%s }}', [kind]),
    'push-to-registry': true,
  },
};

local manifest_job(name, kind, env, parents) = {
  local attest = !std.objectHas(env, 'DOCKERHUB'),
  [name]: {
    name: name,
    'runs-on': 'ubuntu-latest',
    permissions: permissions + (if attest then { attestations: 'write' } else {}),
    needs: parents,
    steps: common_steps + [
      {
        uses: 'actions/download-artifact@v4',
        with: {
          name: parent + '-artifacts',
          path: 'tmp/' + parent + '-artifacts',
        },
      }
      for parent in parents
      if parent != 'cleanup'  // XXX:
    ] + [
      {
        run: 'find tmp',
      },
      {
        run: 'ruby -rjson -e "puts JSON.generate(ARGV.map { JSON.parse(File.read(_1)) }.inject(&:+))" tmp/*-artifacts/built_images.json > tmp/built_images.json',
      },
      {
        id: 'manifest',
        run: 'ruby manifest.rb --' + kind,
        env: env,
        'continue-on-error': std.objectHas(env, 'DOCKERHUB'),
      },
    ] + (if attest then [attest_step('base'), attest_step('dev')] else []),
  },
};

local manifest_subtag_job(pattern) = {
  local parents = [
    pattern_to_job_name('build', pattern { arch: arch })
    for arch in archs
    if arch == 'amd64' || (arch == 'arm64' && pattern.series != '2.6')
  ],
  local env = {
    DIST_FILTER: pattern.distro,
    SERIES_FILTER: pattern.series,
  },
  inner: [
    manifest_job(pattern_to_job_name('manifest-main', pattern), 'subtag', env, parents),

    // For $DOCKERHUB, and schedule it after main manifest job by requiring cleanup job to prioritize main job first.
    manifest_job(pattern_to_job_name('manifest-hub', pattern), 'subtag', env { DOCKERHUB: '1' }, parents + ['cleanup']),
  ],
}.inner;

// N.M.next, from nightly.json.
local manifest_nightly_job(pattern) = manifest_job(
  pattern_to_job_name('manifest-nightly', pattern),
  'subtag',
  { DIST_FILTER: pattern.distro, SERIES_FILTER: pattern.series },
  [
    pattern_to_job_name('build-nightly', pattern { arch: arch })
    for arch in archs
    if arch == 'amd64' || (arch == 'arm64' && pattern.series != '2.6')
  ],
);


local build_jobs = [
  build_job(pattern)
  for pattern in build_job_patterns
] + [
  build_job(pattern, nightly=true)
  for pattern in build_job_patterns
  if std.member(nightly_series, pattern.series)
];

// manifest.rb --latest reads only the default distro of the newest series that is not proposed. NOTE: keep in sync with config.rb
local latest_series = '4.0';
local latest_default_distro = 'noble';
local latest_manifest_parents = [pattern_to_job_name('build', pattern) for pattern in build_job_patterns if pattern.series == latest_series && pattern.distro == latest_default_distro];
local manifest_jobs = std.flattenArrays([
  manifest_subtag_job(pattern)
  for pattern in manifest_subtag_job_patterns
]) + [
  manifest_job('manifest-main-latest', 'latest', {}, latest_manifest_parents),
  manifest_job('manifest-hub-latest', 'latest', { DOCKERHUB: '1' }, latest_manifest_parents),
] + [
  manifest_nightly_job(pattern)
  for pattern in manifest_subtag_job_patterns
  if std.member(nightly_series, pattern.series)
];

local cleanup_job = {
  cleanup: {
    name: 'cleanup',
    'runs-on': 'ubuntu-latest',
    permissions: { 'id-token': 'write', contents: 'read' },
    // Manifest jobs of series and distros left unbuilt are skipped.
    'if': '${{ !cancelled() && !contains(needs.*.result, \'failure\') }}',
    needs: std.flattenArrays([[y.name for y in std.objectValues(x) if std.startsWith(y.name, 'manifest-main-') || std.startsWith(y.name, 'manifest-nightly-')] for x in manifest_jobs]),
    steps: common_steps + [
      {
        run: 'curl -Ssfo cleanup.rb https://raw.githubusercontent.com/sorah/config/2fb9659b9e7e7c754ecda359c45ab24458a84860/bin/sorah-aws-ecr-public-cleanup',
      },
      {
        run: 'gem i aws-sdk-ecrpublic',
      },
      {
        run: 'ruby cleanup.rb ruby',
      },
    ],
  },
};


// A push that changes only versions.json builds just what it changed; see plan.rb.
local plan_job = {
  plan: {
    name: 'plan',
    'runs-on': 'ubuntu-latest',
    permissions: { contents: 'read' },
    outputs: {
      all: '${{ steps.plan.outputs.all }}',
      targets: '${{ steps.plan.outputs.targets }}',
    },
    steps: [
      { uses: 'actions/checkout@v3', with: { 'fetch-depth': 0 } },
      { uses: 'ruby/setup-ruby@v1', with: { 'ruby-version': '3.3' } },
      {
        id: 'plan',
        run: 'ruby plan.rb',
        env: { BEFORE: '${{ github.event.before }}' },
      },
    ],
  },
};

local jobs = [plan_job] + build_jobs + manifest_jobs + [
  cleanup_job,
];

{
  name: 'docker-build',
  on: {
    schedule: [{ cron: '18 7 2,12,22 * *' }],
    push: { branches: ['master'] },
    workflow_dispatch: {},
  },
  jobs: std.foldl(function(r, i) r + i, jobs, {}),
}
