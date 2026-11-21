"""Exercise the actual index/search helper, including a conflicting process cwd."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

TOOL=Path(__file__).resolve().parents[1]/'bin/quickseek-files'


@unittest.skipUnless(shutil.which('fd') and shutil.which('plocate-build'), 'fd and plocate required')
class FileSearchTests(unittest.TestCase):
    def test_glob_is_not_expanded_in_helper_working_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory)
            home=base/'home';home.mkdir()
            cwd=base/'cwd';cwd.mkdir()
            for name in ['main.rs','other.rs','main.py','part1.rs','part2.rs','partx.rs','my main.rs']:
                (home/name).touch()
            (cwd/'main.rs').touch()
            env={**os.environ,'HOME':str(home),'XDG_CONFIG_HOME':str(base/'config'),'XDG_CACHE_HOME':str(base/'cache')}
            subprocess.run([str(TOOL),'index'],env=env,cwd=cwd,check=True,capture_output=True)
            def names(query):
                result=subprocess.check_output([str(TOOL),'search',query],env=env,cwd=cwd,text=True)
                return {Path(line.split('\t',1)[1]).name for line in result.splitlines()}
            self.assertEqual(names('*.rs'),{'main.rs','other.rs','part1.rs','part2.rs','partx.rs','my main.rs'})
            self.assertEqual(names('part?.rs'),{'part1.rs','part2.rs','partx.rs'})
            self.assertEqual(names('part[12].rs'),{'part1.rs','part2.rs'})
            self.assertEqual(names('main *.rs'),{'main.rs','my main.rs'})
            self.assertEqual(names('main'),{'main.rs','main.py','my main.rs'})


if __name__=='__main__':unittest.main()
