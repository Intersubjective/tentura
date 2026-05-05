import sys
import chromadb
from sentence_transformers import SentenceTransformer

DEVICE = "cuda"
model = SentenceTransformer("all-MiniLM-L6-v2", device=DEVICE)

client = chromadb.PersistentClient(path="./chroma_db")
collection = client.get_collection("codebase")

query = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else "how does gameplay work"
n_results = int(sys.argv[-1]) if sys.argv[-1].isdigit() else 5

embedding = model.encode(query, device=DEVICE, convert_to_numpy=True).tolist()
results = collection.query(query_embeddings=[embedding], n_results=n_results)

for i, (doc, meta, dist) in enumerate(zip(
    results["documents"][0],
    results["metadatas"][0],
    results["distances"][0]
)):
    print("=" * 60)
    print(f"#{i+1} | {meta['file']}:{meta['start_line']}-{meta['end_line']} | {meta['class']}.{meta['method']} | dist: {dist:.4f}")
    print("=" * 60)
    lines = doc.split('\n')
    print('\n'.join(lines[:20]))
    if len(lines) > 20:
        print(f"... ({len(lines) - 20} more lines)")
    print()
