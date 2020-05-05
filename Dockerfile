FROM <%= base %>:<%= distro %>

ENV LANG C.UTF-8
ENV DEBIAN_FRONTEND noninteractive

# Versions
ARG RUBY=<%= ruby %>
ARG DEB_RUBY_DEFAULT=<%= deb_ruby_default %>
ARG DEB_RUBY=<%= deb_ruby %>
ARG BUNDLER1_VERSION="~> 1"
ARG BUNDLER2_VERSION="~> 2"

COPY files/sorah-ruby.pem /etc/sorah-ruby.pem
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends --no-install-suggests gnupg2 \
  && apt-key add /etc/sorah-ruby.pem \
  && echo "deb http://cache.ruby-lang.org/lab/sorah/deb/ <%= distro %> main" > /etc/apt/sources.list.d/sorah-ruby.list \
  && apt-get update \
  && apt-get install --no-install-recommends --no-install-suggests -y \
  ca-certificates \
  ruby=${DEB_RUBY_DEFAULT} \
  ruby${RUBY}=${DEB_RUBY} \
  libruby${RUBY}=${DEB_RUBY} \
  ruby${RUBY}-gems=${DEB_RUBY} \
  && apt-get remove --purge -y gnupg2 \
  && apt-get remove --purge --auto-remove -y \
  && rm -rf /var/lib/apt/lists/*

RUN gem install bundler --no-doc -v "${BUNDLER1_VERSION}"
RUN gem install bundler --no-doc -v "${BUNDLER2_VERSION}"

COPY files/unicorn.conf.rb /etc/unicorn.conf
COPY files/puma.rb /etc/puma.rb
