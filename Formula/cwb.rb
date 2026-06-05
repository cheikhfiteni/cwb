# This file is kept here as a reference. The canonical copy that Homebrew
# reads lives in the cheikhfiteni/homebrew-tap repo at Formula/cwb.rb.
# Copy it there (with url + sha256 updated) when cutting a release.
class Cwb < Formula
  desc "High-level wrapper around coding-agent CLIs using isolated git worktrees"
  homepage "https://github.com/cheikhfiteni/cwb"
  url "https://github.com/cheikhfiteni/cwb/archive/refs/tags/v1.4.0.tar.gz"
  sha256 "PLACEHOLDER_RUN_curl_sL_URL_shasum_a_256"
  license "MIT"

  head "https://github.com/cheikhfiteni/cwb.git", branch: "main"

  def install
    prefix.install "cwb", "lib"
    (bin/"cwb").write <<~EOS
      #!/usr/bin/env bash
      source "#{opt_prefix}/cwb"
      cwb "$@"
    EOS
    chmod 0755, bin/"cwb"
  end

  def caveats
    <<~EOS
      cwb is installed as a command on PATH.

      If you previously installed cwb by sourcing it from your shell profile,
      remove this line and open a new shell:

        source "#{opt_prefix}/cwb"
    EOS
  end

  test do
    output = shell_output("#{bin}/cwb --version")
    assert_match "cwb", output
  end
end
