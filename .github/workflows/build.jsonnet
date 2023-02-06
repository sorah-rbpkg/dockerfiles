local matrix = {
  distro: ['bionic', 'focal', 'jammy', 'bullseye', 'buster', 'bookworm'],
  series: ['2.6', '2.7', '3.0', '3.1', '3.2'],
};

local common_steps = [
  {
    run: |||
      mkdir -p ~/.docker\n
      echo '{"experimental": "enabled"}' > ~/.docker/config.json
    |||,
  },
  {
    uses: 'ruby/setup-ruby@v1',
    with: { 'ruby-version': '3.1' },
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

local build_job_matrix = matrix { arch: ['amd64', 'arm64'] };
local build_job_patterns = [
  { series: series, distro: distro, arch: arch }
  for arch in build_job_matrix.arch
  for distro in build_job_matrix.distro
  for series in build_job_matrix.series
];

local manifest_subtag_job_patterns = [
  { series: series, distro: distro }
  for distro in build_job_matrix.distro
  for series in build_job_matrix.series
];

local build_job(pattern) =
  local name = std.format('build-%s-%s-%s', [pattern.series, pattern.distro, pattern.arch]);
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
            name: name + '_built-images.json',
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
          name: parent + '_built_images.json',
          path: 'tmp/' + name,
        },
      }
      for parent in parents
    ] + [
      {
        run: 'ruby -rjson -e "puts JSON.generate(ARGV.map { JSON.parse(File.read(_1)) }.inject(&:+))" tmp/build-*_built_images.json > tmp/built_images.json',
      },
      {
        run: 'ruby manifest.rb --pull --' + kind,
        env: env,
      },
    ],
  },
};

local manifest_subtag_job(pattern) = {
  local name = std.format('manifest-%s-%s', [pattern.series, pattern.distro]),
  local parents = [std.format('build-%s-%s-%s', [pattern.series, pattern.distro, arch]) for arch in build_job_matrix.arch],
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
  manifest_job('manifest-latest', 'latest', {}, [job._name for job in build_jobs]),
];

{
  name: 'docker-build',
  on: {
    schedule: [{ cron: '18 7 2,12,22 * *' }],
    push: { branches: ['master'] },
  },
  jobs: std.foldl(function(r, i) r + i, jobs, {}),
}
