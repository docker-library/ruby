FROM ruby:1.9.3

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

ONBUILD ADD Gemfile /usr/src/app/
ONBUILD ADD Gemfile.lock /usr/src/app/
ONBUILD RUN bundle install --system

ONBUILD ADD . /usr/src/app
