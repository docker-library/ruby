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
		echo >&2 "error: cannot determine sha for $version (tried all of ${allVersions[*]})"
		exit 1
	fi

	echo "$version: $fullVersion; $shaVal"

	export fullVersion shaVal
	json="$(jq <<<"$json" -c '
		.[env.version] = {
			version: env.fullVersion,
			sha256: env.shaVal,
			variants: [
				(
					"buster",
					if env.rcVersion == "2.6" then
						"stretch"
					else empty end
				| ., "slim-" + .), # https://github.com/docker-library/ruby/pull/142#issuecomment-320012893
				(
					"3.14",
					"3.13"
				| "alpine" + .)
			],
		}
	')"
done

jq <<<"$json" -S . > versions.json
