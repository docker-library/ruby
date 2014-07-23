FROM ruby:2.1.2

ONBUILD ADD . /usr/src/app
ONBUILD WORKDIR /usr/src/app
ONBUILD RUN [ ! -e Gemfile ] || bundle install --system --jobs 4
