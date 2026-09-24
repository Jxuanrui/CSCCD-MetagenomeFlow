from pathlib import Path


def get_data_dir(repo_path):
    return Path(repo_path) / "mcp" / "data" / "literature"
