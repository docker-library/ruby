#!/usr/bin/env bash
set -Eeuo pipefail

declare -A aliases=(
	[2.5]='2 latest'
	[2.6-rc]='rc'
)

defaultDebianSuite='stretch'
declare -A debianSuites=(
	[2.2]='jessie'
	[2.3]='jessie'
	[2.4]='jessie'
)
defaultAlpineVersion='3.7'
declare -A alpineVersions=(
	[2.2]='3.4'
	[2.3]='3.4'
)

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( */ )
versions=( "${versions[@]%/}" )

# sort version numbers with highest first
IFS=$'\n'; versions=( $(echo "${versions[*]}" | sort -rV) ); unset IFS

# get the most recent commit which modified any of "$@"
fileCommit() {
	git log -1 --format='format:%H' HEAD -- "$@"
}

# get the most recent commit which modified "$1/Dockerfile" or any file COPY'd from "$1/Dockerfile"
dirCommit() {
	local dir="$1"; shift
	(
		cd "$dir"
		fileCommit \
			Dockerfile \
			$(git show HEAD:./Dockerfile | awk '
				toupper($1) == "COPY" {
					for (i = 2; i < NF; i++) {
						print $i
					}
				}
			')
	)
}

getArches() {
	local repo="$1"; shift
	local officialImagesUrl='https://github.com/docker-library/official-images/raw/master/library/'

	eval "declare -g -A parentRepoToArches=( $(
		find -name 'Dockerfile' -exec awk '
				toupper($1) == "FROM" && $2 !~ /^('"$repo"'|scratch|microsoft\/[^:]+)(:|$)/ {
					print "'"$officialImagesUrl"'" $2
				}
			' '{}' + \
			| sort -u \
			| xargs bashbrew cat --format '[{{ .RepoName }}:{{ .TagName }}]="{{ join " " .TagEntry.Architectures }}"'
	) )"
}
getArches 'ruby'

cat <<-EOH
# this file is generated via https://github.com/docker-library/ruby/blob/$(fileCommit "$self")/$self

Maintainers: Tianon Gravi <admwiggin@gmail.com> (@tianon),
             Joseph Ferguson <yosifkit@gmail.com> (@yosifkit)
GitRepo: https://github.com/docker-library/ruby.git
EOH

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

for version in "${versions[@]}"; do
	debianSuite="${debianSuites[$version]:-$defaultDebianSuite}"
	alpineVersion="${alpineVersions[$version]:-$defaultAlpineVersion}"

	for v in \
		{stretch,jessie}{,/slim,/onbuild} \
		alpine{3.7,3.6,3.4} \
	; do
		dir="$version/$v"
		variant="$(basename "$v")"

		if [ "$variant" = 'slim' ]; then
			# convert "slim" into "slim-jessie"
			# https://github.com/docker-library/ruby/pull/142#issuecomment-320012893
			variant="$variant-$(basename "$(dirname "$v")")"
		fi

		[ -f "$dir/Dockerfile" ] || continue

		commit="$(dirCommit "$dir")"

		versionDockerfile="$dir/Dockerfile"
		versionCommit="$commit"
		if [ "$variant" = 'onbuild' ]; then
			versionDockerfile="$(dirname "$dir")/Dockerfile"
			versionCommit="$(dirCommit "$(dirname "$versionDockerfile")")"
		fi
		fullVersion="$(git show "$versionCommit":"$versionDockerfile" | awk '$1 == "ENV" && $2 == "RUBY_VERSION" { print $3; exit }')"

		versionAliases=(
			$fullVersion
			$version
			${aliases[$version]:-}
		)

		variantAliases=( "${versionAliases[@]/%/-$variant}" )
		case "$variant" in
			"$debianSuite")
				variantAliases+=( "${versionAliases[@]}" )
				;;
			*-"$debianSuite")
				variantAliases+=( "${versionAliases[@]/%/-${variant%-$debianSuite}}" )
				;;
			"alpine${alpineVersion}")
				variantAliases+=( "${versionAliases[@]/%/-alpine}" )
				;;
		esac
		variantAliases=( "${variantAliases[@]//latest-/}" )

		case "$v" in
			*/onbuild)
				variantParent="$(awk 'toupper($1) == "FROM" { print $2 }' "$(dirname "$dir")/Dockerfile")"
				variantArches="${parentRepoToArches[$variantParent]}"
				;;
			*)
				variantParent="$(awk 'toupper($1) == "FROM" { print $2 }' "$dir/Dockerfile")"
				variantArches="${parentRepoToArches[$variantParent]}"
				;;
		esac

		echo
		cat <<-EOE
			Tags: $(join ', ' "${variantAliases[@]}")
			Architectures: $(join ', ' $variantArches)
			GitCommit: $commit
			Directory: $dir
		EOE
	done
done
