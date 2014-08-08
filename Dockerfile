FROM buildpack-deps

RUN useradd -g users user

RUN apt-get update && apt-get install -y bison procps \
  && rm -rf /var/lib/apt/lists/*

# some of ruby's build scripts are written in ruby
# we purge this later to make sure our final image uses what we just built
RUN apt-get update && apt-get install -y ruby \
  && rm -rf /var/lib/apt/lists/*

ADD . /usr/src/ruby
WORKDIR /usr/src/ruby
RUN chown -R user:users .

USER user
RUN autoconf && ./configure --disable-install-doc
RUN make -j"$(nproc)"
RUN make check
USER root

# purge the system ruby now so we can install our newly built ruby
RUN apt-get purge -y ruby

RUN make install

# skip installing gem documentation
RUN echo 'gem: --no-rdoc --no-ri' >> /.gemrc

RUN gem install bundler
