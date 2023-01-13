#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
	json='{}'
else
	json="$(< versions.json)"
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
	export version rcVersion

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
					&& [ -n "$versionReleasePage" ] \
					&& shaVal="$(curl -fsSL "https://www.ruby-lang.org/$versionReleasePage" | grep "ruby-$tryVersion.tar.xz" -A 5)" \
					&& shaVal="$(awk <<<"$shaVal" '$1 == "SHA256:" { print $2; exit }')" \
					&& [ -n "$shaVal" ]
			} \
			|| {
				versionReleasePage="$(echo "$newsPage" | grep -oE '<a href="[^"]+">Ruby '"$tryVersion"' Released</a>' | cut -d'"' -f2)" \
					&& [ -n "$versionReleasePage" ] \
					&& shaVal="$(curl -fsSL "https://www.ruby-lang.org/$versionReleasePage" | grep "ruby-$tryVersion.tar.xz" -A 5)" \
					&& shaVal="$(awk <<<"$shaVal" '$1 == "SHA256:" { print $2; exit }')" \
					&& [ -n "$shaVal" ]
			} \
		; then
			fullVersion="$tryVersion"
			break
		fi
	done

	if [ -z "$fullVersion" ]; then
		echo >&2 "error: cannot determine sha for $version (tried all of ${allVersions[*]})"
		exit 1
	fi

	echo "$version: $fullVersion; $shaVal"

	export fullVersion shaVal
	doc="$(jq -nc '
		{
			version: env.fullVersion,
			sha256: env.shaVal,
			variants: [
				(
					"bullseye",
					"buster",
					empty # trailing comma hack
				| ., "slim-" + .), # https://github.com/docker-library/ruby/pull/142#issuecomment-320012893
				(
					# Alpine 3.17 defaults to OpenSSL 3 which is not supported (yet?) by Ruby 2.7 or 3.0
					# https://bugs.ruby-lang.org/issues/18658
					# https://github.com/docker-library/ruby/pull/392#issuecomment-1329896174
					if [ "2.7", "3.0" ] | index(env.version) then empty else
						"3.17",
						empty # trailing comma hack
					end,
					"3.16",
					empty # trailing comma hack
				| "alpine" + .)
			],
		}
	')"

	case "$rcVersion" in
		2.7 | 3.0 | 3.1) ;;
		*)
			# YJIT
			doc="$(jq <<<"$doc" -sc '
				.[1][].arches? |= if . then with_entries(select(.key as $arch | [
					# https://github.com/ruby/ruby/blob/v3_2_0/doc/yjit/yjit.md ("currently supported for macOS and Linux on x86-64 and arm64/aarch64 CPUs")
					# https://github.com/ruby/ruby/blob/v3_2_0/configure.ac#L3757-L3761
					"amd64",
					"arm64v8",
					empty # trailing comma
				] | index($arch))) else empty end
				| add
			' - rust.json)"
			;;
	esac

	json="$(jq <<<"$json" -c --argjson doc "$doc" '.[env.version] = $doc')"
done

jq <<<"$json" -S . > versions.json
