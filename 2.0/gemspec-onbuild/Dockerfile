FROM ruby:2.0.0-p576

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

ONBUILD ADD . /usr/src/app
ONBUILD RUN bundle install --system

