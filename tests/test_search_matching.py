"""Run the actual JavaScript matcher with Node, without copying its implementation."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('node'), 'Node required for JS tests')
class MatchingTests(unittest.TestCase):
    def test_russian_keys_reach_engine_navigation(self):
        engine=(ROOT/'Engine.qml').read_text()
        start=engine.index('    function onKey(')
        end=engine.index('    signal inputRequested()',start)
        source=(ROOT/'Fuzzy.js').read_text().replace('.pragma library','')
        checks=source+"\nconst Fuzzy = { navigationLetter };\n" if 'function navigationLetter' in source else source+"\nconst Fuzzy = {};\n"
        checks += "const Qt = new Proxy({Key_J:74,Key_K:75,ControlModifier:0x4000000}, {get:(o,k)=>o[k]??-1}); let shown=true,listMode=true,prompt=null; const steps=[]; function move(d){steps.push(d);};\n"
        checks += engine[start:end]
        checks += "\nonKey(0x41e,0,true,true,'о'); onKey(0x41b,0,true,true,'л'); require('node:assert/strict').deepEqual(steps,[1,-1]);"
        result=subprocess.run(['node','-e',checks],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)

    def test_file_patterns(self):
        source=(ROOT/'Fuzzy.js').read_text().replace('.pragma library','')
        checks=r'''
const assert = require('node:assert/strict');
for (const [query, name, expected] of [
    ['*.rs', 'main.rs', true], ['*.rs', 'main.py', false],
    ['*.rs', 'my main.RS', true], ['part?.rs', 'part1.rs', true],
    ['part?.rs', 'part12.rs', false], ['part[12].rs', 'part2.rs', true],
    ['part[12].rs', 'partx.rs', false], ['part[!12].rs', 'partx.rs', true],
    ['main *.rs', 'my main.rs', true], ['*', 'anything.txt', true],
    ['[x', '[x', true], ['file(1)*', 'file(1).rs', true]
]) assert.equal(filePatternScore(query, name) > 0, expected, query + ' / ' + name);
assert.equal(navigationLetter('о'), 'j');
assert.equal(navigationLetter('л'), 'k');
assert.equal(navigationLetter('О'), 'j');
assert.equal(navigationLetter('j'), 'j');
assert.equal(navigationLetter('k'), 'k');
'''
        result=subprocess.run(['node','-e',source+checks],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)


if __name__=='__main__':unittest.main()
