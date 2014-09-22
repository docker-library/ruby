FROM buildpack-deps:wheezy

RUN apt-get update && apt-get install -y curl procps && rm -rf /var/lib/apt/lists/*

ENV RUBY_MAJOR 1.9
ENV RUBY_VERSION 1.9.3-p547

# some of ruby's build scripts are written in ruby
# we purge this later to make sure our final image uses what we just built
RUN apt-get update \
	&& apt-get install -y bison ruby \
	&& rm -rf /var/lib/apt/lists/* \
	&& mkdir -p /usr/src/ruby \
	&& curl -SL "http://cache.ruby-lang.org/pub/ruby/$RUBY_MAJOR/ruby-$RUBY_VERSION.tar.bz2" \
		| tar -xjC /usr/src/ruby --strip-components=1 \
	&& cd /usr/src/ruby \
	&& autoconf \
	&& ./configure --disable-install-doc \
	&& make \
	&& apt-get purge -y --auto-remove bison ruby \
	&& make install \
	&& rm -r /usr/src/ruby

# skip installing gem documentation
RUN echo 'gem: --no-rdoc --no-ri' >> /.gemrc

RUN gem install bundler

CMD [ "irb" ]
