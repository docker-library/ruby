#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

releasesPage="$(curl -fsSL 'https://www.ruby-lang.org/en/downloads/releases/')"
newsPage="$(curl -fsSL 'https://www.ruby-lang.org/en/news/')" # occasionally, releases don't show up on the Releases page (see https://github.com/ruby/www.ruby-lang.org/blob/master/_data/releases.yml)
# TODO consider parsing https://github.com/ruby/www.ruby-lang.org/blob/master/_data/downloads.yml as well

for version in "${versions[@]}"; do
	rcGrepV='-v'
	rcVersion="${version%-rc}"
	if [ "$rcVersion" != "$version" ]; then
		rcGrepV=
	fi

	IFS=$'\n'; allVersions=( $(
		curl -fsSL --compressed "https://cache.ruby-lang.org/pub/ruby/$rcVersion/" \
			| grep -oE '["/]ruby-'"$rcVersion"'.[^"]+\.tar\.xz' \
			| sed -r 's!^["/]ruby-([^"]+)[.]tar[.]xz!\1!' \
			| grep $rcGrepV -E 'preview|rc' \
			| sort -ruV
	) ); unset IFS

	fullVersion=
	shaVal=
	for tryVersion in "${allVersions[@]}"; do
		if \
			{
				versionReleasePage="$(grep "<td>Ruby $tryVersion</td>" -A 2 <<<"$releasesPage" | awk -F '"' '$1 == "<td><a href=" { print $2; exit }')" \
					&& [ "$versionReleasePage" ] \
					&& shaVal="$(curl -fsSL "https://www.ruby-lang.org/$versionReleasePage" |tac|tac| grep "ruby-$tryVersion.tar.xz" -A 5 | awk '$1 == "SHA256:" { print $2; exit }')" \
					&& [ "$shaVal" ]
			} \
			|| {
				versionReleasePage="$(echo "$newsPage" | grep -oE '<a href="[^"]+">Ruby '"$tryVersion"' Released</a>' | cut -d'"' -f2)" \
					&& [ "$versionReleasePage" ] \
					&& shaVal="$(curl -fsSL "https://www.ruby-lang.org/$versionReleasePage" |tac|tac| grep "ruby-$tryVersion.tar.xz" -A 5 | awk '$1 == "SHA256:" { print $2; exit }')" \
					&& [ "$shaVal" ]
			} \
		; then
			fullVersion="$tryVersion"
			break
		fi
	done

	if [ -z "$fullVersion" ]; then
		echo >&2 "warning: cannot determine sha for $version (tried all of ${allVersions[*]}); skipping"
		continue
	fi

	echo "$version: $fullVersion; $shaVal"

	for v in \
		alpine{3.13,3.12} \
		{stretch,buster}{/slim,} \
	; do
		dir="$version/$v"
		variant="$(basename "$v")"

		[ -d "$dir" ] || continue

		case "$variant" in
			slim|windowsservercore) template="$variant"; tag="$(basename "$(dirname "$dir")")" ;;
			alpine*) template='alpine'; tag="${variant#alpine}" ;;
			*) template='debian'; tag="$variant" ;;
		esac
		template="Dockerfile-${template}.template"

		if [ "$variant" = 'slim' ]; then
			tag+='-slim'
		fi

		sed -r \
			-e 's!%%VERSION%%!'"$version"'!g' \
			-e 's!%%FULL_VERSION%%!'"$fullVersion"'!g' \
			-e 's!%%SHA256%%!'"$shaVal"'!g' \
			-e 's/^(FROM (debian|buildpack-deps|alpine)):.*/\1:'"$tag"'/' \
			"$template" > "$dir/Dockerfile"

		case "$v" in
			# https://packages.debian.org/sid/libgdbm-compat-dev (needed for "dbm" core module, but only in Buster+)
			stretch/slim)
				sed -i -e '/libgdbm-compat-dev/d' "$dir/Dockerfile"
				;;
		esac

		# https://github.com/docker-library/ruby/issues/246
		if [ "$rcVersion" = '2.5' ]; then
			rubygems='3.0.3'
			sed -ri \
				-e 's!%%RUBYGEMS%%!'"$rubygems"'!g' \
				"$dir/Dockerfile"
		else
			sed -ri -e '/RUBYGEMS_VERSION/d' "$dir/Dockerfile"
		fi
	done
done
