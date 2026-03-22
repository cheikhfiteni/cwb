# This file is kept here as a reference. The canonical copy that Homebrew
# reads lives in the cheikhfiteni/homebrew-tap repo at Formula/cwb.rb.
# Copy it there (with url + sha256 updated) when cutting a release.
class Cwb < Formula
  desc "High-level wrapper around coding-agent CLIs using isolated git worktrees"
  homepage "https://github.com/cheikhfiteni/cwb"
  url "https://github.com/cheikhfiteni/cwb/archive/refs/tags/v1.4.0.tar.gz"
  sha256 "PLACEHOLDER_RUN_curl_sL_URL_shasum_a_256"
  license "MIT"

  def install
    prefix.install "cwb", "lib"
  end

  def caveats
    <<~EOS
      Add the following to your shell profile (~/.zshrc or ~/.bashrc):

        source "#{opt_prefix}/cwb"

      Then reload your shell:

        source ~/.zshrc
    EOS
  end

  test do
    output = shell_output("bash -c 'source #{opt_prefix}/cwb && cwb --version'")
    assert_match "cwb", output
  end
end
