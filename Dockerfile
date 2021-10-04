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

RUN apt-get update \
  && apt-get upgrade -y \
  && echo "deb [signed-by=/usr/local/share/keyrings/sorah-rbpkg.gpg] http://cache.ruby-lang.org/lab/sorah/deb/ <%= distro %> main" > /etc/apt/sources.list.d/sorah-ruby.list \
  && apt-get update \
  && apt-get install --no-install-recommends --no-install-suggests -y \
  ca-certificates \
  ruby=${DEB_RUBY_DEFAULT} \
  ruby${RUBY}=${DEB_RUBY} \
  libruby${RUBY}=${DEB_RUBY} \
  ruby${RUBY}-gems=${DEB_RUBY} \
  tzdata \
  && rm -rf /var/lib/apt/lists/*

RUN gem install bundler --no-doc -v "${BUNDLER1_VERSION}"
RUN gem install bundler --no-doc -v "${BUNDLER2_VERSION}"

COPY files/unicorn.conf.rb /etc/unicorn.conf
COPY files/puma.rb /etc/puma.rb
