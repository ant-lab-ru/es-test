"""Самопроверка пяти проверок 4.1. Синтетический обмен живёт только в /tmp."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PROJECT = "411-i2c-spi"
ID = ("i2c_read_reg 0x76 0xD0", "i2c: addr 0x76 reg 0xD0 value 0x60")
SPI_ID = ("spi_read 0x00 0xD0", "spi: cs 0x00 command 0xD0 value 0x60")
I2C_ON = ("i2c_write_reg 0x42 0x00 0x65", "i2c: addr 0x42 reg 0x00 sent 0x65")
I2C_OFF = ("i2c_write_reg 0x42 0x01 0x00", "i2c: addr 0x42 reg 0x01 sent 0x00")
I2C_STATE = "i2c_read_reg 0x42 0x01"
SPI_STATE = "spi_read 0x01 0x81 0x64"
READ_I2C_ON = (I2C_STATE, "i2c: addr 0x42 reg 0x01 value 0x01")
READ_I2C_OFF = (I2C_STATE, "i2c: addr 0x42 reg 0x01 value 0x00")
READ_SPI_ON = (SPI_STATE, "spi: cs 0x01 command 0x81 value 0x01")
READ_SPI_OFF = (SPI_STATE, "spi: cs 0x01 command 0x81 value 0x00")
I2C_HELP = ("help list of commands", "i2c_write_reg <address> <register> <value>",
            "i2c_read_reg <address> <register>")
SPI_HELP = ("spi_write <cs> <command> <value>", "spi_read <cs> <command> [pause_us]")
SCENARIOS = {
    1: [ID],
    2: [SPI_ID],
    4: [ID, I2C_ON, READ_I2C_ON, I2C_OFF, READ_I2C_OFF],
    5: [ID, ("i2c_read_reg 0x43 0x01", "error: i2c transfer"),
        ("spi_write 0x01 0x00 0x65", "spi: cs 0x01 command 0x00 sent 0x65"),
        READ_I2C_ON, I2C_OFF, READ_SPI_OFF, I2C_ON, READ_SPI_ON],
}

def fixture(stage, steps, separator=" ", spi_mode="BME280"):
    header = f"задание: 4.1.{stage}\nпроект: {PROJECT}\nустройство: 2e8a:000a\nсерийный номер: 11111111\n"
    if stage == 2 and spi_mode is not None:
        header += f"режим SPI: {spi_mode}\n"
    commands = I2C_HELP if stage == 1 else I2C_HELP + SPI_HELP
    rows = [separator.join(("0", "-->", "help"))]
    rows.extend(separator.join(("0.050", "<--", line)) for line in commands)
    for i, (command, response) in enumerate(steps, start=1):
        rows.append(separator.join((str(i), "-->", command)))
        rows.append(separator.join((f"{i}.050", "<--", response)))
    return header + "\n".join(rows) + "\n"

def main():
    env = {k: v for k, v in os.environ.items() if k not in ("PICO_SDK_PATH", "CHECKS_JSON")}
    with tempfile.TemporaryDirectory(prefix="lesson-4-1-") as tmp:
        repo = Path(tmp)
        project = repo / PROJECT
        shutil.copytree(ROOT / "es-student" / PROJECT, project,
                        ignore=shutil.ignore_patterns("build", "*.log"))
        count = 0

        def run(stage, expected):
            nonlocal count
            command = ROOT / "es-test/checks" / f"check-4-1-{stage}.sh"
            proc = subprocess.run([str(command), str(repo)], env=env, text=True,
                                  capture_output=True)
            assert proc.returncode == expected, proc.stdout + proc.stderr
            count += 1
            return proc.stdout

        def log_path(stage):
            return project / f"device-4-1-{stage}.log"

        run(3, 0)
        for stage in (1, 2, 4, 5):
            run(stage, 1)
        for stage, steps in SCENARIOS.items():
            path = log_path(stage)
            good = fixture(stage, steps, "\t")
            path.write_text(good)
            run(stage, 0)
            path.write_text(good.replace("2e8a:000a", "0000:0000"))
            run(stage, 1)
            path.write_text(good.replace("0x60", "0x58", 1))
            run(stage, 1)
            path.write_text(good.replace("help list of commands", "help", 1))
            run(stage, 1)
            path.write_text(good.replace("0.050\t<--\ti2c_read_reg", "3.050\t<--\ti2c_read_reg", 1))
            run(stage, 1)
            path.write_text(fixture(stage, steps[:-1]))
            run(stage, 1)
            path.write_text(good)
        path = log_path(2)
        spi_zero = (SPI_ID[0], SPI_ID[1].replace("value 0x60", "value 0x00"))
        path.write_text(fixture(2, [spi_zero], spi_mode="без датчика"))
        assert "⚠️" in run(2, 0)
        path.write_text(fixture(2, [spi_zero]))
        run(2, 1)
        path.write_text(fixture(2, [SPI_ID], spi_mode="без датчика"))
        run(2, 1)
        path.write_text(fixture(2, [SPI_ID], spi_mode=None))
        run(2, 1)
        path.write_text(fixture(2, [SPI_ID]).replace(PROJECT, "411-spi-i2c"))
        run(2, 1)
        path.write_text(fixture(2, [SPI_ID]))

        path = log_path(5)
        order = list(SCENARIOS[5])
        order[4], order[5] = order[5], order[4]
        path.write_text(fixture(5, order))
        run(5, 1)
        path.write_text(fixture(5, SCENARIOS[5]).replace("8.050", "11.050"))
        run(5, 1)
        path.write_text(fixture(5, SCENARIOS[5]))
        p = project / "platform/platform.c"
        source = p.read_text()
        for stage, token in ((1, "i2c_read_timeout_us"), (2, "spi_read_blocking"),
                             (2, "gpio_pull_down"),
                             (3, "multicore_launch_core1"), (4, "i2c_read_byte_raw"),
                             (5, "spi_set_slave")):
            p.write_text(source.replace(token, "replaced") + f"\n// {token}(spi1, true)\n")
            run(stage, 1)
        p.write_text(source)
        main_source = project / "main.c"
        main_source.write_text(main_source.read_text().replace("api_handle(command);", "// api_handle(command);"))
        run(1, 1)
        print(f"Пройдено сценариев 4.1: {count}")

if __name__ == "__main__":
    main()
