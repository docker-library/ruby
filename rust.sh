#!/usr/bin/env bash
set -Eeuo pipefail

rustupVersion="$(curl -fsSL 'https://static.rust-lang.org/rustup/release-stable.toml')"
rustupVersion="$(awk <<<"$rustupVersion" -F "[ ='\"]+" '$1 == "version" { print $2; exit }')"
[ -n "$rustupVersion" ]
export rustupVersion
echo "rustup: $rustupVersion"

json="$(jq -nc '
	{
		rustup: {
			version: env.rustupVersion,
			arches: (
				[
					# https://github.com/rust-lang/rustup/blob/1.25.1/doc/src/installation/other.md
					# (filtering out windows, darwin, bsd, illumos, android, etc - just linux gnu and musl)
					"aarch64-unknown-linux-gnu",
					"aarch64-unknown-linux-musl",
					"arm-unknown-linux-gnueabi",
					"arm-unknown-linux-gnueabihf",
					"armv7-unknown-linux-gnueabihf",
					"i686-unknown-linux-gnu",
					"mips-unknown-linux-gnu",
					"mips64-unknown-linux-gnuabi64",
					"mips64el-unknown-linux-gnuabi64",
					"mipsel-unknown-linux-gnu",
					"powerpc-unknown-linux-gnu",
					"powerpc64-unknown-linux-gnu",
					"powerpc64le-unknown-linux-gnu",
					"s390x-unknown-linux-gnu",
					"x86_64-unknown-linux-gnu",
					"x86_64-unknown-linux-musl",
					# TODO find a good source for scraping these instead of hard-coding them
					empty # trailing comma
				]
				| map(
					split("-") as $split
					| $split[0] as $arch
					| $split[-1] as $libc
					| {
						"aarch64": "arm64v8",
						"arm": ("arm32v" + if ($libc | endswith("hf")) then "6" else "5" end),
						"armv7": "arm32v7",
						"i686": "i386",
						"mips64el": "mips64le",
						"powerpc64le": "ppc64le",
						"s390x": "s390x",
						"x86_64": "amd64",
						# TODO windows? (we do not compile on/for Windows right now)
					}[$arch] as $bashbrewArch
					| select($bashbrewArch)
					| {
						($bashbrewArch): {
							(if $libc == "musl" then "musl" else "glibc" end): ({
								"arch": .,
								"url": "https://static.rust-lang.org/rustup/archive/\(env.rustupVersion)/\(.)/rustup-init",
							} | .sha256 = .url + ".sha256"),
						},
					}
				)
				| reduce .[] as $map ({}; . * $map)
			),
		},
	}
')"

urls="$(jq <<<"$json" -r '[ .. | .sha256? | select(. and startswith("http")) | @sh ] | join(" ")')"
eval "urls=( $urls )"
for url in "${urls[@]}"; do
	sha256="$(curl -fsSL "$url")"
	sha256="${sha256%% *}"
	[ -n "$sha256" ]
	export url sha256
	json="$(jq <<<"$json" -c 'walk(if . == env.url then env.sha256 else . end)')"
done

# TODO https://static.rust-lang.org/dist/channel-rust-1.66.toml -> scrape stable to know which version is stable but we can scrape other minors to get the latest patch if we needed an older one for some reason (like an older version of Ruby needing an older Rust or a newer Rust no longer working on our older distros, etc)

rustVersion="$(curl -fsSL 'https://static.rust-lang.org/dist/channel-rust-stable.toml' | grep -E '^(\[|(version|(xz_)?(url|hash|available))[[:space:]]*=)')"
rustVersion="$(awk <<<"$rustVersion" -F "[ ='\"]+" '
	/^\[/ { pkg = $0; next }
	pkg == "[pkg.rust]" && $1 == "version" { print $2; exit }
')"
[ -n "$rustVersion" ]
export rustVersion
echo "rust: $rustVersion"
# TODO also scrape available "[pkg.rust.target.*-linux-*]" so we can cross-reference available target arches with rustup

json="$(jq <<<"$json" -c '.rust = { version: env.rustVersion }')"

jq <<<"$json" -S . > rust.json
