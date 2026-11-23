import json
import os
import subprocess
import tempfile
import time
import unittest
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PG_DATA = "/var/lib/postgresql/data"
TEST_VOLUME = "pg_scope_runtime"


class PostgresOwnerScopeRuntimeTest(unittest.TestCase):
    def test_enforcement_is_on_in_dev_and_unset_in_production(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        override = Path(directory.name) / "postgres-storage.json"
        override.write_text(
            json.dumps({
                "services": {
                    "postgres": {"volumes": [f"{TEST_VOLUME}:{PG_DATA}"]},
                },
                "volumes": {TEST_VOLUME: {}},
            }),
            encoding="utf-8",
        )

        settings = {
            "production": self.read_startup_setting("prod", override),
            "development": self.read_startup_setting("dev", override),
        }
        self.assertIn(settings["production"], (None, ""), settings)
        self.assertEqual(settings["development"], "on", settings)

    def read_startup_setting(self, environment, override):
        name = f"tentura-{environment}-pg-scope-{uuid.uuid4().hex[:12]}"
        compose = [
            "docker", "compose", "-p", name,
            "-f", f"compose.{environment}.yaml", "-f", str(override),
        ]
        env = {**os.environ, "POSTGRES_PASSWORD": f"test-{name}"}
        # Verify isolation before starting the service. Production normally
        # bind-mounts the deployment's data directory.
        config = self.run_command(
            compose + ["config", "--format", "json", "postgres"], env,
        )
        mounts = json.loads(config.stdout)["services"]["postgres"]["volumes"]
        self.assertEqual(
            [
                (mount["type"], mount["source"])
                for mount in mounts
                if mount["target"] == PG_DATA
            ],
            [("volume", TEST_VOLUME)],
        )
        self.addCleanup(self.run_command, compose + ["down", "--volumes"], env)
        self.addCleanup(self.remove_container, name, env)
        self.run_command(
            compose + ["run", "--no-deps", "--detach", "--rm", "--name", name, "postgres"],
            env,
        )

        query = [
            "docker", "exec", name, "psql", "-XAt", "-v", "ON_ERROR_STOP=1",
            "-h", "127.0.0.1", "-U", "postgres", "-d", "postgres", "-c",
            "SELECT json_build_array(current_setting('tentura.owner_scope_enforce', true))",
        ]
        # TCP only becomes available after initdb's temporary server exits.
        deadline = time.monotonic() + 30
        while True:
            result = self.run_command(query, env, check=False, timeout=3)
            if result.returncode == 0:
                return json.loads(result.stdout)[0]
            if time.monotonic() >= deadline:
                self.fail(f"{environment} PostgreSQL did not accept connections: {result.stderr}")
            time.sleep(0.25)

    def remove_container(self, name, env):
        result = self.run_command(
            ["docker", "rm", "--force", "--volumes", name], env, check=False,
        )
        if result.returncode != 0 and "No such container" not in result.stderr:
            self.fail(result.stderr)

    def run_command(self, argv, env, *, check=True, timeout=45):
        result = subprocess.run(
            argv, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout,
        )
        if check and result.returncode:
            self.fail(f"{argv}: {result.stderr}")
        return result


if __name__ == "__main__":
    unittest.main()
