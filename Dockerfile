FROM <%= base %>:<%= distro %>

ENV LANG C.UTF-8
ENV DEBIAN_FRONTEND noninteractive

# Versions
ARG RUBY=<%= ruby %>
ARG DEB_RUBY_DEFAULT=<%= deb_ruby_default %>
ARG DEB_RUBY=<%= deb_ruby %>
ARG BUNDLER1_VERSION="~> 1"
ARG BUNDLER2_VERSION="~> 2"

COPY files/sorah-rbpkg.gpg /usr/local/share/keyrings/sorah-rbpkg.gpg
COPY files/apt-preference-priority /etc/apt/preferences.d/90-sorah-rbpkg-preference

RUN apt-get update \
  && apt-get upgrade -y \
  && echo "deb [signed-by=/usr/local/share/keyrings/sorah-rbpkg.gpg] http://cache.ruby-lang.org/lab/sorah/deb/ <%= distro %> main" > /etc/apt/sources.list.d/sorah-ruby.list \
  && echo "Package: src:ruby-defaults\nPin: version $DEB_RUBY_DEFAULT\nPin-Priority: 999" > /etc/apt/preferences.d/91-sorah-rbpkg-ruby-defaults \
  && grep -r . /etc/apt/preferences.d \
  && apt-get update \
  && apt-get install --no-install-recommends --no-install-suggests -y \
  ca-certificates \
  ruby=${DEB_RUBY_DEFAULT} \
  ruby${RUBY}=${DEB_RUBY} \
  libruby${RUBY}=${DEB_RUBY} \
  ruby${RUBY}-gems=${DEB_RUBY} \
  tzdata \
  && rm -rf /var/lib/apt/lists/*

RUN if dpkg --compare-versions "${RUBY}" '<=' '3.3'; then gem install bundler --no-doc -v "${BUNDLER1_VERSION}"; fi
RUN if dpkg --compare-versions "${RUBY}" '<=' '2.7'; then gem install bundler --no-doc -v "2.4.22"; else gem install bundler --no-doc -v "${BUNDLER2_VERSION}"; fi

<% if distro == 'jammy' && distro == 'bookworm' %>
# (/root/.bundle/config) https://github.com/protocolbuffers/protobuf/issues/11935
RUN bundle config set --global build.google-protobuf --with-cflags=-fno-lto
<% end %>

COPY files/unicorn.conf.rb /etc/unicorn.conf
COPY files/puma.rb /etc/puma.rb
