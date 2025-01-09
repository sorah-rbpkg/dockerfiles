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

local splitWithSpace = function(s) [token for token in std.split(s, ' ') if token != ''];
local matrix = [
  { series: '2.7', distro: splitWithSpace('bionic focal               buster                  '), arm: true },
  { series: '3.0', distro: splitWithSpace('bionic focal jammy         buster bullseye         '), arm: true },
  { series: '3.1', distro: splitWithSpace('bionic focal jammy                bullseye         '), arm: true },
  { series: '3.2', distro: splitWithSpace('       focal jammy noble          bullseye bookworm'), arm: true },
  { series: '3.3', distro: splitWithSpace('       focal jammy noble          bullseye bookworm'), arm: true },
  { series: '3.4', distro: splitWithSpace('             jammy noble                   bookworm'), arm: true },
];
local archs = ['amd64', 'arm64'];

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

local build_job(pattern) =
  local name = pattern_to_job_name('build', pattern);
  {
    _name:: name,
    [name]: {
      name: name,
      'runs-on': 'ubuntu-latest',
      permissions: { 'id-token': 'write', contents: 'read' },
      steps: common_steps + [
        { uses: 'docker/setup-qemu-action@v2' },
        {
          run: 'ruby build.rb --pull --push',
          env: {
            SERIES_FILTER: pattern.series,
            DIST_FILTER: pattern.distro,
            ARCH_FILTER: pattern.arch,
          },
        },
        {
          uses: 'actions/upload-artifact@v3',
          with: {
            name: name + '-artifacts',
            path: 'tmp/built_images.json',
            'retention-days': 1,
          },
        },
      ],
    },
  };

local manifest_job(name, kind, env, parents) = {
  [name]: {
    name: name,
    'runs-on': 'ubuntu-latest',
    permissions: { 'id-token': 'write', contents: 'read' },
    needs: parents,
    steps: common_steps + [
      {
        uses: 'actions/download-artifact@v3',
        with: {
          name: parent + '-artifacts',
          path: 'tmp/' + parent + '-artifacts',
        },
      }
      for parent in parents
    ] + [
      {
        run: 'find tmp',
      },
      {
        run: 'ruby -rjson -e "puts JSON.generate(ARGV.map { JSON.parse(File.read(_1)) }.inject(&:+))" tmp/*-artifacts/built_images.json > tmp/built_images.json',
      },
      {
        run: 'ruby manifest.rb --pull --' + kind,
        env: env,
      },
    ],
  },
};

local manifest_subtag_job(pattern) = {
  local name = pattern_to_job_name('manifest', pattern),
  local parents = [
    pattern_to_job_name('build', pattern { arch: arch })
    for arch in archs
    if arch == 'amd64' || (arch == 'arm64' && pattern.series != '2.6')
  ],
  local env = {
    DIST_FILTER: pattern.distro,
    SERIES_FILTER: pattern.series,
  },
  inner: manifest_job(name, 'subtag', env, parents),
}.inner;


local build_jobs = [
  build_job(pattern)
  for pattern in build_job_patterns
];

local jobs = build_jobs + [
  manifest_subtag_job(pattern)
  for pattern in manifest_subtag_job_patterns
] + [
  manifest_job('manifest-latest', 'latest', {}, [pattern_to_job_name('build', pattern) for pattern in build_job_patterns if pattern.series == matrix[std.length(matrix) - 1].series]),
];

{
  name: 'docker-build',
  on: {
    schedule: [{ cron: '18 7 2,12,22 * *' }],
    push: { branches: ['master'] },
  },
  jobs: std.foldl(function(r, i) r + i, jobs, {}),
}
