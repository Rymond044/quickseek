import importlib.machinery
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader('system_info', str(Path(__file__).resolve().parents[1] / 'bin/quickseek-system-info'))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class ClocksTest(unittest.TestCase):
    def snapshot(self, props=None, error=False):
        calls = [subprocess.CompletedProcess([], 0, props), subprocess.CompletedProcess([], 0, '800')]
        with patch.dict(module.os.environ, {'XDG_SESSION_ID': '3'}), patch.object(module.time, 'time', return_value=1000), patch.object(module.time, 'clock_gettime', side_effect=[900, 300]), patch.object(module.subprocess, 'run', side_effect=OSError() if error else calls):
            return module.snapshot()

    def test_sleep_is_counted_only_in_elapsed_and_session(self):
        data = self.snapshot(f'Type=wayland\nClass=user\nUser={module.os.getuid()}\nTimestamp=example')
        self.assertEqual(data, dict(elapsed=900, awake=300, bootTime=100, session=200))

    def test_non_graphical_session_is_not_reported(self):
        self.assertIsNone(self.snapshot(f'Type=tty\nClass=user\nUser={module.os.getuid()}\nTimestamp=example')['session'])

    def test_other_users_session_is_not_reported(self):
        self.assertIsNone(self.snapshot('Type=wayland\nClass=user\nUser=99999\nTimestamp=example')['session'])

    def test_missing_logind_keeps_clock_metrics(self):
        data = self.snapshot(error=True)
        self.assertIsNone(data['session'])
        self.assertEqual(data['awake'], 300)


if __name__ == '__main__':
    unittest.main()
