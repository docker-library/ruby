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

yq='./.yq'
# https://github.com/mikefarah/yq/releases
# TODO detect host architecture
yqUrl='https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64'
yqSha256='0d6aaf1cf44a8d18fbc7ed0ef14f735a8df8d2e314c4cc0f0242d35c0a440c95'
if command -v yq &> /dev/null; then
	# TODO verify that the "yq" in PATH is https://github.com/mikefarah/yq, not the python-based version you'd get from "apt-get install yq" somehow?  maybe they're compatible enough for our needs that it doesn't matter?
	yq='yq'
elif [ ! -x "$yq" ] || ! sha256sum <<<"$yqSha256 *$yq" --quiet --strict --check; then
	wget -qO "$yq.new" "$yqUrl"
	sha256sum <<<"$yqSha256 *$yq.new" --quiet --strict --check
	chmod +x "$yq.new"
	"$yq.new" --version
	mv "$yq.new" "$yq"
fi

releases="$(
	wget -qO- 'https://github.com/ruby/www.ruby-lang.org/raw/master/_data/releases.yml' \
		| "$yq" -r '@json' # this *should* work on both the Go-based "yq" we download and the Python-based "yq" available from Debian's APT repo
)"

for version in "${versions[@]}"; do
	rcGrepV='-v'
	rcVersion="${version%-rc}"
	if [ "$rcVersion" != "$version" ]; then
		rcGrepV=
	fi
	export version rcVersion

	doc="$(jq <<<"$releases" -c '
		map(
			select(
				.version
				# exact versions ("3.1.0-preview1") should match exactly but "X.Y" or "X.Y-rc" should fuzzy match appropriately
				| . == env.version or (
					(
						startswith(env.rcVersion + ".")
						or startswith(env.rcVersion + "-")
					) and (
						contains("preview") or contains("rc")
						| if env.version == env.rcVersion then not else . end
					)
				)
			)
		)
		| first // empty
	')"

	if [ -z "$doc" ]; then
		echo >&2 "warning: skipping/removing '$version' (does not appear to exist upstream)"
		json="$(jq <<<"$json" -c '.[env.version] = null')"
		continue
	fi

	fullVersion="$(jq <<<"$doc" -r '.version')"
	echo "$version: $fullVersion"

	if [ "$rcVersion" != "$version" ] && gaFullVersion="$(jq <<<"$json" -er '.[env.rcVersion] | if . then .version else empty end')"; then
		# Ruby pre-releases have only been for .0 since ~2011, so if our pre-release now has a relevant GA, it should go away 👀
		# just in case, we'll also do a version comparison to make sure we don't have a pre-release that's newer than the relevant GA
		latestVersion="$({ echo "$fullVersion"; echo "$gaFullVersion"; } | sort -V | tail -1)"
		if [[ "$fullVersion" == "$gaFullVersion"* ]] || [ "$latestVersion" = "$gaFullVersion" ]; then
			# "x.y.z-rc1" == x.y.z*
			json="$(jq <<<"$json" -c 'del(.[env.version])')"
			continue
		fi
	fi

	doc="$(jq <<<"$doc" -c '
		.variants = [
			(
				# https://bugs.ruby-lang.org/issues/18658
				# https://github.com/docker-library/ruby/pull/392#issuecomment-1329896174
				if  "3.0" == env.version then
					"bullseye",
					"buster"
				else
					"bookworm",
					"bullseye",
					empty # trailing comma hack
				end
			| ., "slim-" + .), # https://github.com/docker-library/ruby/pull/142#issuecomment-320012893
			(
				# Alpine 3.17+ defaults to OpenSSL 3 which is not supported by Ruby 3.0
				# https://bugs.ruby-lang.org/issues/18658
				# https://github.com/docker-library/ruby/pull/392#issuecomment-1329896174
				if  "3.0" == env.version then "3.16" else
					"3.19",
					"3.18",
					empty # trailing comma hack
				end
			| "alpine" + .)
		]
	')"

	case "$rcVersion" in
		3.0 | 3.1) ;;
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

	# make sure pre-release versions have a placeholder for GA
	if [ "$version" != "$rcVersion" ]; then
		json="$(jq <<<"$json" -c '.[env.rcVersion] //= null')"
	fi
done

jq <<<"$json" 'to_entries | sort_by(.key) | from_entries' > versions.json
