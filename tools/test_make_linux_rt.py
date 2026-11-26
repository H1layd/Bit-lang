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
    timed = result.split("\n_bit_tcp_connect_timed:", 1)[1].split(
        "\n_bit_tcp_listen:", 1
    )[0]
    assert "mov edx, 4                     # SO_ERROR" in timed, "Linux SO_ERROR must be 4"
    assert "mov edx, 4103" not in timed, "Darwin SO_ERROR leaked into Linux"
    assert "or eax, 2048" in timed, "Linux O_NONBLOCK must be 2048"
    assert "and eax, -2049" in timed, "Linux O_NONBLOCK must be cleared"
print("Linux runtime: scoped AT_FDCWD and timed connect constants passed")
