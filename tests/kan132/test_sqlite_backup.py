"""Exercise root-only backup against isolated synthetic files, never K3s data."""
import os
from pathlib import Path
import sqlite3
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[2]
pytestmark = pytest.mark.skipif(os.geteuid() != 0, reason='Root-only backup; CI runs this isolated fixture as root')


@pytest.fixture
def source(tmp_path):
    data = tmp_path / 'k3s'
    db = data / 'server/db/state.db'
    db.parent.mkdir(parents=True)
    with sqlite3.connect(db) as conn:
        conn.execute('CREATE TABLE evidence (value TEXT)')
        conn.execute('INSERT INTO evidence VALUES (?)', ('synthetic-private-fixture',))
    (data / 'server/token').write_text('synthetic-token')
    config = tmp_path / 'config.yaml'
    config.write_text('data-dir: /synthetic\n')
    return {'K3S_DATA_DIR': str(data), 'K3S_CONFIG_FILE': str(config),
            'BACKUP_ROOT': str(tmp_path / 'backups')}


def backup(source):
    return subprocess.run(['bash', str(ROOT / 'scripts/kan-132/backup-sqlite.sh')],
                          env={**os.environ, **source}, capture_output=True, text=True)


def test_consistent_confidential_backup_and_no_overwrite(source):
    result = backup(source)
    assert result.returncode == 0, result.stdout + result.stderr
    folder = next(Path(source['BACKUP_ROOT']).iterdir())
    files = ['datastore/state.db', 'datastore/config.yaml', 'secret/server-token', 'SHA256SUMS', 'README.txt']
    contents = {name: (folder / name).read_bytes() for name in files}
    assert folder.stat().st_mode & 0o777 == 0o700
    for name in files:
        assert (folder / name).stat().st_mode & 0o777 == 0o600
    with sqlite3.connect(folder / 'datastore/state.db') as conn:
        assert conn.execute('SELECT value FROM evidence').fetchone()[0] == 'synthetic-private-fixture'
    subprocess.run(['sha256sum', '--check', 'SHA256SUMS'], cwd=folder, check=True, capture_output=True)
    assert backup(source).returncode == 0
    assert len(list(Path(source['BACKUP_ROOT']).iterdir())) == 2
    assert contents == {name: (folder / name).read_bytes() for name in files}


def test_refuses_stale_sqlite_after_etcd_conversion(source):
    (Path(source['K3S_DATA_DIR']) / 'server/db/etcd/member').mkdir(parents=True)
    result = backup(source)
    assert result.returncode != 0
    assert not Path(source['BACKUP_ROOT']).exists()


def test_refuses_external_datastore_configuration(source):
    Path(source['K3S_CONFIG_FILE']).write_text('datastore-endpoint: postgres://synthetic\n')
    result = backup(source)
    assert result.returncode != 0
    assert not Path(source['BACKUP_ROOT']).exists()
