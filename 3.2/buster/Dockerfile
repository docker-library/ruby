#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM buildpack-deps:buster

# skip installing gem documentation
RUN set -eux; \
	mkdir -p /usr/local/etc; \
	{ \
		echo 'install: --no-document'; \
		echo 'update: --no-document'; \
	} >> /usr/local/etc/gemrc

ENV LANG C.UTF-8
ENV RUBY_MAJOR 3.2
ENV RUBY_VERSION 3.2.0
ENV RUBY_DOWNLOAD_SHA256 d2f4577306e6dd932259693233141e5c3ec13622c95b75996541b8d5b68b28b4

# some of ruby's build scripts are written in ruby
#   we purge system ruby later to make sure our final image uses what we just built
RUN set -eux; \
	\
	yjit=; \
	debArch="$(uname -m)"; \
	\
	export RUSTUP_HOME=/tmp/rustup; \
	export CARGO_HOME=/tmp/cargo; \
	PATH=$CARGO_HOME/bin:$PATH; \
	rustArch=${debArch}-unknown-linux-gnu; \
	case "$debArch" in \
		x86_64)  yjit=1; RUST_VERSION=1.66; rustupSha256='5cc9ffd1026e82e7fb2eec2121ad71f4b0f044e88bca39207b3f6b769aaa799c' ;; \
		aarch64) yjit=1; RUST_VERSION=1.66; rustupSha256='e189948e396d47254103a49c987e7fb0e5dd8e34b200aa4481ecc4b8e41fb929';; \
	esac; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		bison \
		dpkg-dev \
		libgdbm-dev \
		ruby \
	; \
	rm -rf /var/lib/apt/lists/*; \
	\
	case "$yjit" in \
		1) wget https://static.rust-lang.org/rustup/archive/1.25.1/${rustArch}/rustup-init; \
		   echo "${rustupSha256} *rustup-init" | sha256sum --check --strict; \
		   chmod +x rustup-init; \
		   ./rustup-init -y --no-modify-path --profile minimal --default-toolchain $RUST_VERSION --default-host ${rustArch}; \
		   rm rustup-init; \
		   cargo --version; \
		   rustc --version ;; \
	esac; \
	\
	wget -O ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR%-rc}/ruby-$RUBY_VERSION.tar.xz"; \
	echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.xz" | sha256sum --check --strict; \
	\
	mkdir -p /usr/src/ruby; \
	tar -xJf ruby.tar.xz -C /usr/src/ruby --strip-components=1; \
	rm ruby.tar.xz; \
	\
	cd /usr/src/ruby; \
	\
# hack in "ENABLE_PATH_CHECK" disabling to suppress:
#   warning: Insecure world writable dir
	{ \
		echo '#define ENABLE_PATH_CHECK 0'; \
		echo; \
		cat file.c; \
	} > file.c.new; \
	mv file.c.new file.c; \
	\
	autoconf; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	./configure \
		--build="$gnuArch" \
		--disable-install-doc \
		--enable-shared \
		${yjit:+--enable-yjit} \
	; \
	make -j "$(nproc)"; \
	make install; \
	\
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark > /dev/null; \
	find /usr/local -type f -executable -not \( -name '*tkinter*' \) -exec ldd '{}' ';' \
		| awk '/=>/ { print $(NF-1) }' \
		| sort -u \
		| grep -vE '^/usr/local/lib/' \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u \
		| xargs -r apt-mark manual \
	; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf $RUSTUP_HOME; \
	rm -rf $CARGO_HOME; \
	\
	cd /; \
	rm -r /usr/src/ruby; \
# verify we have no "ruby" packages installed
	if dpkg -l | grep -i ruby; then exit 1; fi; \
	[ "$(command -v ruby)" = '/usr/local/bin/ruby' ]; \
# rough smoke test
	ruby --version; \
	gem --version; \
	bundle --version

# don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_SILENCE_ROOT_WARNING=1 \
	BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $GEM_HOME/bin:$PATH
# adjust permissions of a few directories for running "gem install" as an arbitrary user
RUN mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"

CMD [ "irb" ]
