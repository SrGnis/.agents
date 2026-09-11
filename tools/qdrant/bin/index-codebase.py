#!/usr/bin/env python3
"""
Qdrant codebase indexer.

Parses code with tree-sitter, generates semantic embeddings, and stores
chunks in Qdrant with content-addressable deduplication using git blob hashes.

Usage:
    index-codebase.py <repo-root>                    # Incremental full scan
    index-codebase.py <repo-root> --diff <diff>      # Index specific changes (git diff-tree output)
    index-codebase.py <repo-root> --branch <name>    # Index for specific branch
    index-codebase.py <repo-root> --reindex           # Force full re-index
    index-codebase.py --resolve-identity <repo-root>  # Print project identity key
    index-codebase.py --write-config <repo-root>      # Write per-project opencode MCP config
"""

import argparse
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

STATE_DIR = Path.home() / ".agents" / "tools" / "qdrant" / "state"

SUPPORTED_EXTENSIONS = {
    ".py": "python",
    ".js": "javascript",
    ".jsx": "javascript",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".rs": "rust",
    ".go": "go",
    ".java": "java",
    ".c": "c",
    ".cpp": "cpp",
    ".cc": "cpp",
    ".h": "c",
    ".hpp": "cpp",
    ".rb": "ruby",
    ".php": "php",
    ".kt": "kotlin",
    ".kts": "kotlin",
    ".swift": "swift",
    ".cs": "c_sharp",
    ".scala": "scala",
    ".lua": "lua",
    ".hs": "haskell",
    ".sh": "bash",
    ".bash": "bash",
    ".md": "markdown",
    ".yaml": "yaml",
    ".yml": "yaml",
    ".toml": "toml",
}

SYMBOL_QUERY = {
    "python": """
    (function_definition name: (identifier) @name) @func
    (class_definition name: (identifier) @name) @class
    """,
    "javascript": """
    (function_declaration name: (identifier) @name) @func
    (class_declaration name: (identifier) @name) @class
    (method_definition name: (property_identifier) @name) @method
    (arrow_function) @func
    """,
    "typescript": """
    (function_declaration name: (identifier) @name) @func
    (class_declaration name: (type_identifier) @name) @class
    (method_definition name: (property_identifier) @name) @method
    (interface_declaration name: (type_identifier) @name) @interface
    (type_alias_declaration name: (type_identifier) @name) @type
    (arrow_function) @func
    """,
    "rust": """
    (function_item name: (identifier) @name) @func
    (impl_item type: (type_identifier) @name) @impl
    (struct_item name: (type_identifier) @name) @struct
    (enum_item name: (type_identifier) @name) @enum
    (trait_item name: (type_identifier) @name) @trait
    """,
    "go": """
    (function_declaration name: (identifier) @name) @func
    (method_declaration name: (field_identifier) @name) @method
    (type_declaration (type_spec name: (type_identifier) @name)) @type
    """,
    "java": """
    (method_declaration name: (identifier) @name) @method
    (class_declaration name: (identifier) @name) @class
    (interface_declaration name: (identifier) @name) @interface
    """,
    "c": """
    (function_definition declarator: (function_declarator declarator: (identifier) @name)) @func
    (struct_specifier name: (type_identifier) @name) @struct
    """,
    "cpp": """
    (function_definition declarator: (function_declarator declarator: (identifier) @name)) @func
    (class_specifier name: (type_identifier) @name) @class
    (struct_specifier name: (type_identifier) @name) @struct
    """,
    "ruby": """
    (method name: (identifier) @name) @func
    (class name: (constant) @name) @class
    (singleton_method name: (identifier) @name) @func
    """,
    "php": """
    (function_definition name: (name) @name) @func
    (class_declaration name: (name) @name) @class
    (method_declaration name: (name) @name) @method
    """,
    "kotlin": """
    (function_declaration (simple_identifier) @name) @func
    (class_declaration (simple_identifier) @name) @class
    """,
    "swift": """
    (function_declaration (simple_identifier) @name) @func
    (class_declaration (type_identifier) @name) @class
    (struct_declaration (type_identifier) @name) @struct
    """,
    "c_sharp": """
    (method_declaration name: (identifier) @name) @method
    (class_declaration name: (identifier) @name) @class
    """,
    "scala": """
    (function_definition name: (identifier) @name) @func
    (class_definition name: (identifier) @name) @class
    """,
    "lua": """
    (function_declaration name: (identifier) @name) @func
    """,
    "haskell": """
    (function name: (variable) @name) @func
    (data_type name: (type) @name) @type
    """,
    "bash": """
    (function_definition name: (word) @name) @func
    """,
    "markdown": """
    (atx_heading) @heading
    """,
    "yaml": """
    (block_mapping_pair key: (flow_node) @name) @section
    """,
    "toml": """
    (table (bare_key) @name) @section
    """,
}


def log(msg: str, verbose: bool = False, force: bool = False):
    if verbose or force:
        print(f"[qdrant-index] {msg}", file=sys.stderr)


def resolve_project_identity(repo_root: str) -> tuple[str, str]:
    """Returns (project_key, collection_name). Canonical resolution used everywhere."""
    try:
        result = subprocess.run(
            ["git", "worktree", "list", "--porcelain"],
            capture_output=True, text=True, cwd=repo_root
        )
        for line in result.stdout.splitlines():
            if line.startswith("worktree "):
                repo_root = line[len("worktree "):]
                break
    except Exception:
        pass

    remote_url = None
    try:
        result = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            capture_output=True, text=True, cwd=repo_root
        )
        if result.returncode == 0 and result.stdout.strip():
            remote_url = result.stdout.strip()
    except Exception:
        pass

    if remote_url:
        identity = remote_url
        identity = re.sub(r'^https?://', '', identity)
        identity = re.sub(r'^git@', '', identity)
        identity = re.sub(r'\.git$', '', identity)
        identity = re.sub(r'[:/]', '-', identity)
        project_key = identity
    else:
        path_hash = hashlib.sha256(repo_root.encode()).hexdigest()[:8]
        project_key = f"{os.path.basename(repo_root)}-{path_hash}"

    return project_key, project_key


def git_hash_object(filepath: str, cwd: str = ".") -> str:
    result = subprocess.run(
        ["git", "hash-object", filepath],
        capture_output=True, text=True, cwd=cwd
    )
    return result.stdout.strip()


def load_state(state_path: Path) -> dict:
    if state_path.exists():
        with open(state_path) as f:
            return json.load(f)
    return {}


def save_state(state_path: Path, state: dict):
    state_path.parent.mkdir(parents=True, exist_ok=True)
    with open(state_path, "w") as f:
        json.dump(state, f, indent=2)
        f.write("\n")


def textify(name: str, symbol_type: str, docstring: str, signature: str,
            file_path: str, language: str) -> str:
    """Generate natural language description of a code chunk."""
    def normalize(s: str) -> str:
        s = re.sub(r'([a-z])([A-Z])', r'\1 \2', s)
        s = s.replace('_', ' ')
        return s.strip().lower()

    norm_name = normalize(name)
    norm_type = symbol_type.replace('_', ' ')

    parts = [f"{norm_type} {norm_name}"]

    if docstring:
        doc = docstring.strip().split('\n')[0][:200]
        parts.append(f"that {doc}")

    if signature:
        sig = normalize(signature)[:200]
        parts.append(f"defined as {sig}")

    parts.append(f"in {file_path}")

    text = " ".join(parts)
    tokens = re.split(r'\W+', text)
    tokens = [t for t in tokens if t]
    return " ".join(tokens)


def get_docstring(node, source: bytes) -> str:
    """Extract docstring from a function/class node."""
    for child in node.children:
        if child.type == "expression_statement":
            for sub in child.children:
                if sub.type == "string":
                    return sub.text.decode("utf-8", errors="replace").strip("\"'`")
        if child.type == "block":
            for sub in child.children:
                if sub.type == "expression_statement":
                    for subsub in sub.children:
                        if subsub.type == "string":
                            return subsub.text.decode("utf-8", errors="replace").strip("\"'`")
    return ""


def get_signature(node, source: bytes) -> str:
    """Extract the first line(s) of a symbol as its signature."""
    text = node.text.decode("utf-8", errors="replace")
    lines = text.split('\n')
    sig_lines = []
    for line in lines[:3]:
        stripped = line.strip()
        if stripped:
            sig_lines.append(stripped)
        if '{' in stripped or ':' in stripped and len(sig_lines) > 0:
            break
    return ' '.join(sig_lines)[:300]


def parse_file(filepath: str, language: str) -> list[dict]:
    """Parse a file with tree-sitter and extract code chunks."""
    try:
        from tree_sitter_languages import get_language, get_parser
    except ImportError:
        print("tree-sitter-languages not installed. Run: uv pip install tree-sitter-languages", file=sys.stderr)
        sys.exit(1)

    try:
        parser = get_parser(language)
    except Exception:
        return []

    with open(filepath, "rb") as f:
        source = f.read()

    tree = parser.parse(source)
    lang = get_language(language)

    query_str = SYMBOL_QUERY.get(language)
    if not query_str:
        return []

    try:
        query = lang.query(query_str)
    except Exception:
        return []

    chunks = []
    seen_ranges = set()

    captures = query.captures(tree.root_node)

    # Normalize captures to list of (capture_name, node) tuples
    all_captures = []
    if isinstance(captures, dict):
        for capture_name, nodes in captures.items():
            for node in nodes:
                all_captures.append((capture_name, node))
    elif isinstance(captures, list):
        for item in captures:
            if isinstance(item, tuple) and len(item) == 2:
                node, capture_name = item
                all_captures.append((capture_name, node))

    func_nodes = {}
    for capture_name, node in all_captures:
        if capture_name in ("func", "class", "method", "interface", "type",
                            "impl", "struct", "enum", "trait",
                            "heading", "section"):
            range_key = (node.start_point[0], node.end_point[0])
            if range_key not in seen_ranges:
                seen_ranges.add(range_key)
                func_nodes[range_key] = (capture_name, node)

    for range_key, (symbol_type, node) in func_nodes.items():
        start_line = node.start_point[0] + 1
        end_line = node.end_point[0] + 1

        name = ""
        for child in node.children:
            if child.type in ("identifier", "type_identifier", "property_identifier",
                              "field_identifier", "simple_identifier", "name",
                              "constant", "variable", "word", "bare_key",
                              "heading_content", "flow_node"):
                name = child.text.decode("utf-8", errors="replace")
                break
        if not name and symbol_type == "heading":
            raw = node.text.decode("utf-8", errors="replace")
            name = re.sub(r'^#+\s*', '', raw.split('\n')[0]).strip()
        if not name:
            name = f"<anonymous_{start_line}>"

        code = node.text.decode("utf-8", errors="replace")
        docstring = get_docstring(node, source)
        signature = get_signature(node, source)

        chunks.append({
            "name": name,
            "type": symbol_type,
            "line_from": start_line,
            "line_to": end_line,
            "code": code[:2000],
            "docstring": docstring,
            "signature": signature,
        })

    return chunks


def get_ignored_paths(repo_root: str) -> set[str]:
    """Get paths ignored by git."""
    try:
        result = subprocess.run(
            ["git", "ls-files", "--ignored", "--exclude-standard", "--others"],
            capture_output=True, text=True, cwd=repo_root
        )
        if result.returncode == 0:
            return set(result.stdout.strip().split('\n')) if result.stdout.strip() else set()
    except Exception:
        pass
    return set()


def scan_files(repo_root: str, verbose: bool = False) -> list[str]:
    """Walk the repo and return source files respecting .gitignore."""
    ignored = get_ignored_paths(repo_root)
    files = []

    for dirpath, dirnames, filenames in os.walk(repo_root):
        rel_dir = os.path.relpath(dirpath, repo_root)

        dirnames[:] = [
            d for d in dirnames
            if d not in {'.git', 'node_modules', '__pycache__', '.venv', 'venv',
                         'vendor', 'target', 'dist', 'build', '.tox', '.mypy_cache',
                         '.pytest_cache', '.eggs'}
        ]

        for filename in filenames:
            ext = os.path.splitext(filename)[1].lower()
            if ext not in SUPPORTED_EXTENSIONS:
                continue

            rel_path = os.path.relpath(os.path.join(dirpath, filename), repo_root)

            if rel_path in ignored:
                continue

            files.append(rel_path)

    return files


def make_point_id(file_path: str, blob_hash: str, line_from: int, symbol_name: str) -> str:
    """Content-addressable point ID as UUID. Branch is NOT included — same content = same ID."""
    raw = f"{file_path}:{blob_hash}:{line_from}:{symbol_name}"
    h = hashlib.sha256(raw.encode()).hexdigest()[:32]
    return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


def write_opencode_config(repo_root: str, collection_name: str):
    """Write per-project opencode MCP config, merging with existing."""
    config_dir = os.path.join(repo_root, ".opencode")
    config_path = os.path.join(config_dir, "opencode.json")

    os.makedirs(config_dir, exist_ok=True)

    config = {}
    if os.path.exists(config_path):
        with open(config_path) as f:
            config = json.load(f)

    if "mcp" not in config or not isinstance(config.get("mcp"), dict):
        config["mcp"] = {}

    config["mcp"]["qdrant"] = {
        "type": "local",
        "command": ["uvx", "mcp-server-qdrant"],
        "enabled": True,
        "environment": {
            "QDRANT_URL": "http://localhost:6333",
            "COLLECTION_NAME": collection_name,
            "EMBEDDING_MODEL": "sentence-transformers/all-MiniLM-L6-v2",
            "QDRANT_READ_ONLY": "true",
        }
    }

    if "$schema" not in config:
        config["$schema"] = "https://opencode.ai/config.json"

    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")

    print(f"[qdrant-index] Wrote MCP config to {config_path}", file=sys.stderr)


def create_collection(client, collection_name: str):
    """Create Qdrant collection if it doesn't exist."""
    from qdrant_client import models

    collections = [c.name for c in client.get_collections().collections]
    if collection_name in collections:
        return

    client.create_collection(
        collection_name=collection_name,
        vectors_config={
            "fast-all-minilm-l6-v2": models.VectorParams(
                size=384,
                distance=models.Distance.COSINE,
            )
        },
    )

    client.create_payload_index(
        collection_name=collection_name,
        field_name="branches",
        field_schema=models.PayloadSchemaType.KEYWORD,
    )
    client.create_payload_index(
        collection_name=collection_name,
        field_name="file_path",
        field_schema=models.PayloadSchemaType.KEYWORD,
    )


def embed_texts(texts: list[str]) -> list[list[float]]:
    """Embed texts using FastEmbed."""
    from fastembed import TextEmbedding

    model = TextEmbedding("sentence-transformers/all-MiniLM-L6-v2")
    embeddings = list(model.embed(texts))
    return [e.tolist() for e in embeddings]


def index_files(repo_root: str, branch: str, files: list[str],
                state: dict, client, collection_name: str,
                verbose: bool = False) -> tuple[int, int]:
    """Index a list of files. Returns (indexed_count, skipped_count)."""
    indexed = 0
    skipped = 0

    for rel_path in files:
        full_path = os.path.join(repo_root, rel_path)
        if not os.path.exists(full_path):
            continue

        current_blob = git_hash_object(rel_path, cwd=repo_root)
        branch_state = state.setdefault("branches", {}).get(branch, {})
        file_state = branch_state.get(rel_path, {})

        if file_state.get("blob") == current_blob:
            skipped += 1
            continue

        ext = os.path.splitext(rel_path)[1].lower()
        language = SUPPORTED_EXTENSIONS.get(ext)
        if not language:
            skipped += 1
            continue

        chunks = parse_file(full_path, language)
        if not chunks:
            skipped += 1
            continue

        old_points = file_state.get("points", [])
        if old_points:
            existing = client.retrieve(
                collection_name=collection_name,
                ids=old_points,
                with_payload=True,
            )
            points_to_delete = []
            for point in existing:
                branches = point.payload.get("branches", [])
                if branch in branches:
                    branches.remove(branch)
                if len(branches) == 0:
                    points_to_delete.append(point.id)
                else:
                    client.set_payload(
                        collection_name=collection_name,
                        payload={"branches": branches},
                        points=[point.id],
                    )
            if points_to_delete:
                client.delete(collection_name=collection_name, ids=points_to_delete)

        new_ids = []
        point_data = []

        for chunk in chunks:
            point_id = make_point_id(rel_path, current_blob, chunk["line_from"], chunk["name"])
            new_ids.append(point_id)
            description = textify(
                chunk["name"], chunk["type"], chunk["docstring"],
                chunk["signature"], rel_path, language
            )
            point_data.append({
                "id": point_id,
                "description": description,
                "payload": {
                    "branches": [branch],
                    "file_path": rel_path,
                    "symbol_name": chunk["name"],
                    "symbol_type": chunk["type"],
                    "line_from": chunk["line_from"],
                    "line_to": chunk["line_to"],
                    "code": chunk["code"],
                    "description": description,
                    "document": chunk["code"],
                    "language": language,
                }
            })

        existing_ids = set()
        if new_ids:
            try:
                existing_points = client.retrieve(
                    collection_name=collection_name,
                    ids=new_ids,
                    with_payload=True,
                )
                existing_ids = {p.id for p in existing_points}
                for point in existing_points:
                    branches = point.payload.get("branches", [])
                    if branch not in branches:
                        branches.append(branch)
                        client.set_payload(
                            collection_name=collection_name,
                            payload={"branches": branches},
                            points=[point.id],
                        )
            except Exception:
                pass

        new_points = [d for d in point_data if d["id"] not in existing_ids]
        if new_points:
            texts = [d["description"] for d in new_points]
            vectors = embed_texts(texts)

            from qdrant_client.models import PointStruct
            qdrant_points = [
                PointStruct(
                    id=d["id"],
                    vector={"fast-all-minilm-l6-v2": v},
                    payload=d["payload"],
                )
                for d, v in zip(new_points, vectors)
            ]

            batch_size = 64
            for i in range(0, len(qdrant_points), batch_size):
                client.upsert(
                    collection_name=collection_name,
                    points=qdrant_points[i:i + batch_size],
                )

        state["branches"].setdefault(branch, {})[rel_path] = {
            "blob": current_blob,
            "points": new_ids,
        }
        indexed += 1

    return indexed, skipped


def handle_rename(client, collection_name: str, branch: str,
                  old_path: str, new_path: str, state: dict, verbose: bool = False):
    """Handle file rename — update file_path in payload."""
    full_new = os.path.join(state.get("_repo_root", ""), new_path)
    if not os.path.exists(full_new):
        return

    new_blob = git_hash_object(new_path, cwd=state.get("_repo_root", "."))
    branch_state = state.get("branches", {}).get(branch, {})
    old_state = branch_state.get(old_path, {})
    old_points = old_state.get("points", [])

    if old_points:
        client.set_payload(
            collection_name=collection_name,
            payload={"file_path": new_path},
            points=old_points,
        )

    state["branches"].setdefault(branch, {})[new_path] = {
        "blob": new_blob,
        "points": old_points,
    }
    if old_path in state["branches"].get(branch, {}):
        del state["branches"][branch][old_path]

    log(f"Renamed {old_path} -> {new_path}", verbose)


def handle_delete(client, collection_name: str, branch: str,
                  file_path: str, state: dict, verbose: bool = False):
    """Handle file delete — remove branch from point payloads or delete points."""
    branch_state = state.get("branches", {}).get(branch, {})
    file_state = branch_state.get(file_path, {})
    points = file_state.get("points", [])

    if points:
        existing = client.retrieve(
            collection_name=collection_name,
            ids=points,
            with_payload=True,
        )
        points_to_delete = []
        for point in existing:
            branches = point.payload.get("branches", [])
            if branch in branches:
                branches.remove(branch)
            if len(branches) == 0:
                points_to_delete.append(point.id)
            else:
                client.set_payload(
                    collection_name=collection_name,
                    payload={"branches": branches},
                    points=[point.id],
                )
        if points_to_delete:
            client.delete(collection_name=collection_name, ids=points_to_delete)

    if file_path in state.get("branches", {}).get(branch, {}):
        del state["branches"][branch][file_path]

    log(f"Deleted {file_path}", verbose)


def main():
    parser = argparse.ArgumentParser(description="Qdrant codebase indexer")
    parser.add_argument("repo_root", nargs="?", help="Repository root path")
    parser.add_argument("--resolve-identity", metavar="REPO_ROOT",
                        help="Print project identity key and exit")
    parser.add_argument("--write-config", metavar="REPO_ROOT",
                        help="Write per-project opencode MCP config")
    parser.add_argument("--diff", help="git diff-tree --name-status output for incremental indexing")
    parser.add_argument("--branch", help="Branch name to index (default: current branch)")
    parser.add_argument("--reindex", action="store_true", help="Force full re-index")
    parser.add_argument("--verbose", action="store_true", help="Verbose output")
    args = parser.parse_args()

    if args.resolve_identity:
        project_key, _ = resolve_project_identity(args.resolve_identity)
        print(project_key)
        return

    if args.write_config:
        project_key, collection_name = resolve_project_identity(args.write_config)
        write_opencode_config(args.write_config, collection_name)
        return

    if not args.repo_root:
        parser.error("repo_root is required unless using --resolve-identity or --write-config")

    repo_root = os.path.abspath(args.repo_root)
    project_key, collection_name = resolve_project_identity(repo_root)
    state_path = STATE_DIR / f"{project_key}.json"

    log(f"Project: {project_key}", args.verbose, force=True)
    log(f"Collection: {collection_name}", args.verbose, force=True)
    log(f"State: {state_path}", args.verbose)

    try:
        from qdrant_client import QdrantClient
        client = QdrantClient(url="http://localhost:6333")
        client.get_collections()
    except Exception as e:
        print(f"[qdrant-index] Cannot connect to Qdrant: {e}", file=sys.stderr)
        sys.exit(1)

    create_collection(client, collection_name)

    try:
        result = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, cwd=repo_root
        )
        current_branch = result.stdout.strip() if result.returncode == 0 else "HEAD"
    except Exception:
        current_branch = "HEAD"

    branch = args.branch or current_branch

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    lock_path = str(state_path) + ".lock"

    with open(lock_path, "w") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        try:
            state = load_state(state_path)
            state["_repo_root"] = repo_root

            if args.reindex:
                state.get("branches", {}).pop(branch, None)

            if args.diff:
                diff_lines = args.diff.strip().split('\n')
                indexed = 0
                skipped = 0
                for line in diff_lines:
                    parts = line.strip().split('\t')
                    if len(parts) < 2:
                        continue
                    status = parts[0]

                    if status.startswith('R'):
                        old_path, new_path = parts[1], parts[2]
                        handle_rename(client, collection_name, branch, old_path, new_path, state, args.verbose)
                        idx, skip = index_files(repo_root, branch, [new_path], state, client, collection_name, args.verbose)
                        indexed += idx
                        skipped += skip
                    elif status == 'D':
                        handle_delete(client, collection_name, branch, parts[1], state, args.verbose)
                    else:
                        file_path = parts[1]
                        full_path = os.path.join(repo_root, file_path)
                        if os.path.exists(full_path):
                            idx, skip = index_files(repo_root, branch, [file_path], state, client, collection_name, args.verbose)
                            indexed += idx
                            skipped += skip
                        else:
                            handle_delete(client, collection_name, branch, file_path, state, args.verbose)

                log(f"Indexed: {indexed}, Skipped: {skipped}", args.verbose, force=True)
            else:
                files = scan_files(repo_root, args.verbose)
                log(f"Found {len(files)} source files", args.verbose, force=True)
                indexed, skipped = index_files(repo_root, branch, files, state, client, collection_name, args.verbose)
                log(f"Indexed: {indexed}, Skipped: {skipped}", args.verbose, force=True)

            state.pop("_repo_root", None)
            save_state(state_path, state)

        finally:
            fcntl.flock(lock_file, fcntl.LOCK_UN)


if __name__ == "__main__":
    main()
