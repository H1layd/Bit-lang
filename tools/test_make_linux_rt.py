"""Regression check: an unrelated function must retain Darwin-looking constants."""
from pathlib import Path
import subprocess
import sys
import tempfile


root = Path(__file__).resolve().parent.parent
probe = "\n_bit_linux_scope_probe:\n    mov rdi, -2\n    ret\n"
with tempfile.TemporaryDirectory(prefix="bit-linux-rt-") as folder:
    work = Path(folder)
    (work / "rt").mkdir()
    source = (root / "rt/x86_64.s").read_text()
    (work / "rt/x86_64.s").write_text(source + probe)
    subprocess.run(
        [sys.executable, str(root / "tools/make_linux_rt.py")],
        cwd=work, check=True, stdout=subprocess.DEVNULL,
    )
    result = (work / "rt/x86_64-linux.s").read_text()
    assert probe in result, "AT_FDCWD replacement changed an unrelated function"
    removal = result.split("\n_bit_dir_remove_all:", 1)[1].split(
        "\n_bit_remove_at:", 1
    )[0]
    assert "mov rdi, -100" in removal, "Linux removal needs Linux AT_FDCWD"
print("Linux runtime: AT_FDCWD replacement is scoped")
