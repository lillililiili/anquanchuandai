"""Compile standalone transfer tools against an immutable application artifact; no Maven mutation."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

from migrate import extract_runtime

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--application-jar', required=True, type=Path)
parser.add_argument('--java-home', required=True, type=Path)
parser.add_argument('--work-dir', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix='migration-contract-', dir=args.work_dir) as directory:
    runtime = Path(directory)
    classpath = extract_runtime(args.application_jar, runtime)
    classes = runtime / 'tools'
    classes.mkdir()
    suffix = '.exe' if os.name == 'nt' else ''
    subprocess.run([str(args.java_home / 'bin' / ('javac' + suffix)), '-J-Dfile.encoding=UTF-8', '-encoding', 'UTF-8',
                    '-cp', classpath, '-d', str(classes), str(root / 'MigrationTool.java'), str(root / 'MigrationToolTest.java')], check=True)
    subprocess.run([str(args.java_home / 'bin' / ('java' + suffix)), '-Dfile.encoding=UTF-8', '-Duser.timezone=UTC',
                    '-cp', str(classes) + os.pathsep + classpath, 'MigrationToolTest', str(runtime)], check=True)
