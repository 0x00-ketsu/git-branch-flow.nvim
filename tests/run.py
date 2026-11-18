import os
import pathlib
import subprocess
import tempfile

root = pathlib.Path(tempfile.mkdtemp(prefix="branch-comparison-"))

def git(*args):
    """Run Git in the temporary test repository."""
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()

git("init", "-b", "release")
git("config", "user.name", "Test")
git("config", "user.email", "test@example.invalid")

def commit(name, trailer="Issue: IMS-1"):
    """Create a named fixture commit and return its SHA."""
    (root / name).write_text(name)
    git("add", name)
    git("commit", "-m", name, "-m", trailer)
    return git("rev-parse", "HEAD")

commit("base")
git("switch", "-c", "external")
external = commit("external", "")
git("switch", "release")
git("switch", "-c", "develop")
picked = commit("picked")
commit("pending", "Issue: IMS-1\nDepends-on-commit: " + external[:8])
git("switch", "release")
commit("target-only")
git("update-ref", "refs/remotes/origin/release", "HEAD")
git("config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*")
git("config", "branch.release.remote", "origin")
git("config", "branch.release.merge", "refs/heads/release")
git("cherry-pick", "-x", picked)
env = {**os.environ, "GIT_TEST_REPO": str(root), "EXTERNAL_SHA": external,
       "NVIM_LOG_FILE": "/tmp/nvim-branch-compare.log"}
subprocess.run(["nvim", "--clean", "--headless", "-l", "tests/unpushed.lua"],
               env=env, check=True)
subprocess.run(["nvim", "--clean", "--headless", "-l", "tests/git.lua"],
               env=env, check=True)
git("switch", "--detach")
subprocess.run(["nvim", "--clean", "--headless", "-l", "tests/detached.lua"],
               env=env, check=True)

root = pathlib.Path(tempfile.mkdtemp(prefix="branch-conflict-"))
git("init", "-b", "release")
git("config", "user.name", "Test")
git("config", "user.email", "test@example.invalid")
commit("base")
git("switch", "-c", "develop")
commit("clean")
(root / "base").write_text("develop version")
git("add", "base")
git("commit", "-m", "conflict", "-m", "Issue: IMS-1")
commit("after-conflict")
git("switch", "release")
(root / "base").write_text("release version")
git("add", "base")
git("commit", "-m", "target change", "-m", "Issue: IMS-1")
env["GIT_TEST_REPO"] = str(root)
subprocess.run(["nvim", "--clean", "--headless", "-l", "tests/conflict.lua"],
               env=env, check=True)

root = pathlib.Path(tempfile.mkdtemp(prefix="branch-context-"))
git("init", "-b", "release")
git("config", "user.name", "Test")
git("config", "user.email", "test@example.invalid")
(root / "file").write_text("one\ntwo\nthree\nfour\nfive\n")
git("add", "file")
git("commit", "-m", "base")
git("switch", "-c", "develop")
(root / "file").write_text("one\ntwo\nchanged\nfour\nfive\n")
git("commit", "-am", "change", "-m", "Issue: IMS-2")
source_sha = git("rev-parse", "HEAD")
git("switch", "release")
(root / "file").write_text("different\ntwo\nthree\nfour\nfive\n")
git("commit", "-am", "different context")
git("cherry-pick", source_sha)
assert "+ " + source_sha in git("cherry", "release", "develop")
env["GIT_TEST_REPO"] = str(root)
subprocess.run(["nvim", "--clean", "--headless", "-l", "tests/context.lua"],
               env=env, check=True)

root = pathlib.Path(tempfile.mkdtemp(prefix="branch-conflict-candidates-"))
git("init", "-b", "release")
git("config", "user.name", "Test")
git("config", "user.email", "test@example.invalid")
(root / "file").write_text("initial\n")
git("add", "file")
git("commit", "-m", "base")
git("switch", "-c", "develop")
(root / "file").write_text("prepared\n")
git("commit", "-am", "prepare", "-m", "Issue: IMS-10")
(root / "file").write_text("complete\n")
git("commit", "-am", "complete", "-m", "Issue: IMS-11")
env["CONFLICT_SHA"] = git("rev-parse", "HEAD")
git("switch", "release")
env["GIT_TEST_REPO"] = str(root)
subprocess.run(["nvim", "--clean", "--headless", "-l", "tests/candidates.lua"],
               env=env, check=True)

root = pathlib.Path(tempfile.mkdtemp(prefix="branch-batch-"))
git("init", "-b", "release")
git("config", "user.name", "Test")
git("config", "user.email", "test@example.invalid")
commit("base")
git("switch", "-c", "develop")
(root / "billing-first").write_text("first")
git("add", "billing-first")
git("commit", "-m", "billing first", "-m", "Issue: BILLING-420")
(root / "billing-second").write_text("second")
git("add", "billing-second")
git("commit", "-m", "billing second", "-m", "Issue: BILLING-420")
git("switch", "release")
env["GIT_TEST_REPO"] = str(root)
subprocess.run(["nvim", "--clean", "--headless", "-l", "tests/batch.lua"],
               env=env, check=True)
