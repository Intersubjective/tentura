import os, re, sys
import chromadb
import pathspec
from sentence_transformers import SentenceTransformer

DEVICE = "cuda"
model = SentenceTransformer("all-MiniLM-L6-v2", device=DEVICE)

SOURCE_DIR = os.path.expanduser("./")
FILE_EXT = ".dart"

client = chromadb.PersistentClient(path="./chroma_db")
collection = client.get_or_create_collection("codebase", metadata={"hnsw:space": "cosine"})

ENCODE_BATCH = 128


def load_gitignore_specs(root):
    specs = {}
    for dirpath, _, filenames in os.walk(root):
        if ".gitignore" in filenames:
            with open(os.path.join(dirpath, ".gitignore"), errors="ignore") as f:
                lines = f.read().splitlines()
            specs[dirpath] = pathspec.PathSpec.from_lines("gitwildmatch", lines)
    return specs


def is_ignored(filepath, specs):
    for spec_dir, spec in specs.items():
        try:
            rel = os.path.relpath(filepath, spec_dir)
        except ValueError:
            continue
        if not rel.startswith("..") and spec.match_file(rel):
            return True
    return False


def extract_chunks(filepath):
    with open(filepath, "r", errors="ignore") as f:
        lines = f.readlines()

    chunks = []
    current_class = ""
    i = 0

    while i < len(lines):
        line = lines[i]

        class_match = re.match(
            r'\s*(?:public|private|internal|protected)?\s*(?:abstract|static|sealed|partial)?\s*class\s+(\w+)', line
        )
        if class_match:
            current_class = class_match.group(1)

        method_match = re.match(
            r'\s*(?:public|private|protected|internal|static|virtual|override|abstract|async|sealed|\[.*?\]|\s)*'
            r'[\w<>\[\],\s\?]+\s+(\w+)\s*\(.*?\)',
            line
        )

        if method_match and '{' in ''.join(lines[i:i+3]):
            method_name = method_match.group(1)
            start_line = i + 1
            brace_count = 0
            j = i
            while j < len(lines):
                brace_count += lines[j].count('{') - lines[j].count('}')
                if brace_count <= 0 and '{' in ''.join(lines[i:j+1]):
                    break
                j += 1
            chunk_text = ''.join(lines[i:j+1])
            rel_path = os.path.relpath(filepath, SOURCE_DIR)
            chunk_id = f"{rel_path}:{start_line}-{j+1}:{current_class}.{method_name}"
            chunks.append({
                "id": chunk_id,
                "text": chunk_text.strip(),
                "metadata": {"file": rel_path, "class": current_class, "method": method_name,
                             "start_line": start_line, "end_line": j + 1}
            })
            i = j + 1
        else:
            i += 1

    if not chunks and lines:
        rel_path = os.path.relpath(filepath, SOURCE_DIR)
        chunks.append({
            "id": f"{rel_path}:1-{len(lines)}:{current_class}.file",
            "text": ''.join(lines).strip(),
            "metadata": {"file": rel_path, "class": current_class, "method": "file",
                         "start_line": 1, "end_line": len(lines)}
        })

    return chunks


def upsert_chunks(chunks):
    if not chunks:
        return
    texts = [c["text"] for c in chunks]
    embeddings = model.encode(texts, batch_size=ENCODE_BATCH, show_progress_bar=False,
                              device=DEVICE, convert_to_numpy=True).tolist()
    collection.upsert(
        ids=[c["id"] for c in chunks],
        documents=texts,
        embeddings=embeddings,
        metadatas=[c["metadata"] for c in chunks],
    )


def index_file(filepath):
    rel_path = os.path.relpath(filepath, SOURCE_DIR)
    try:
        existing = collection.get(where={"file": rel_path})
        if existing["ids"]:
            collection.delete(ids=existing["ids"])
    except Exception:
        pass
    chunks = extract_chunks(filepath)
    upsert_chunks(chunks)
    return len(chunks)


def index_all():
    specs = load_gitignore_specs(SOURCE_DIR)
    all_chunks = []
    skipped = 0
    for root, _, files in os.walk(SOURCE_DIR):
        for fname in files:
            if not fname.endswith(FILE_EXT):
                continue
            filepath = os.path.join(root, fname)
            if is_ignored(filepath, specs):
                skipped += 1
                continue
            all_chunks.extend(extract_chunks(filepath))

    print(f"Chunks: {len(all_chunks)} | Skipped (gitignored): {skipped} files")

    BATCH = 500
    for i in range(0, len(all_chunks), BATCH):
        batch = all_chunks[i:i+BATCH]
        upsert_chunks(batch)
        print(f"  {min(i+BATCH, len(all_chunks))}/{len(all_chunks)}", end="\r", flush=True)

    print(f"\nDone. Indexed {len(all_chunks)} chunks from {SOURCE_DIR}")


if __name__ == "__main__":
    if "--single" in sys.argv:
        filepath = sys.argv[sys.argv.index("--single") + 1]
        count = index_file(filepath)
        print(f"Re-indexed {filepath}: {count} chunks")
    else:
        index_all()
