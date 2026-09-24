"""
BM25 sparse retrieval layer for MaxMetagenome RAG.
存储位置: mcp/bm25_data/{collection_name}.pkl
"""

import pickle
import re
from pathlib import Path

from rank_bm25 import BM25Okapi


def _tokenize(text: str) -> list[str]:
    """
    中英混合分词：按空格+标点切分，保留数字和连字符。
    不引入 jieba 等外部分词器。
    """
    text = text.lower()
    tokens = []
    split_pattern = r"[\s　，。！？；：「」【】（）,.;:!?\"'`~@#$%^&*+=|\\/<>[\]{}()]+"
    for chunk in re.split(split_pattern, text):
        if not chunk:
            continue
        cjk = re.sub(r"[^一-鿿]", " ", chunk)
        non_cjk = re.sub(r"[一-鿿]", " ", chunk)
        tokens.extend(c for c in cjk if c.strip())
        tokens.extend(w for w in non_cjk.split() if w.strip())
    return tokens


class BM25Index:
    def __init__(self):
        self._bm25 = None
        self._doc_ids: list[str] = []
        self._corpus_tokens: list[list[str]] = []

    def build(self, documents: list[tuple[str, str]]):
        """
        documents: list of (doc_id, text)
        """
        self._doc_ids = [doc_id for doc_id, _ in documents]
        self._corpus_tokens = [_tokenize(text) for _, text in documents]
        self._bm25 = BM25Okapi(self._corpus_tokens)

    def search(self, query: str, top_k: int = 20) -> list[tuple[str, float]]:
        """
        返回 list of (doc_id, score)，按 score 降序
        """
        if self._bm25 is None:
            return []
        tokens = _tokenize(query)
        if not tokens:
            return []
        scores = self._bm25.get_scores(tokens)
        ranked = sorted(zip(self._doc_ids, scores), key=lambda item: item[1], reverse=True)
        return ranked[:top_k]

    def save(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "wb") as handle:
            pickle.dump(
                {"doc_ids": self._doc_ids, "corpus_tokens": self._corpus_tokens},
                handle,
            )

    def load(self, path) -> bool:
        path = Path(path)
        if not path.exists():
            return False
        with open(path, "rb") as handle:
            data = pickle.load(handle)
        self._doc_ids = data["doc_ids"]
        self._corpus_tokens = data["corpus_tokens"]
        self._bm25 = BM25Okapi(self._corpus_tokens)
        return True


def reciprocal_rank_fusion(ranked_lists: list[list[str]], k: int = 60) -> list[str]:
    """
    RRF 融合多路检索结果。
    ranked_lists: 每个元素是一个 doc_id 列表（按相关性降序）
    返回: 融合后的 doc_id 列表（按融合分降序）
    """
    scores: dict[str, float] = {}
    for ranked in ranked_lists:
        for rank, doc_id in enumerate(ranked, start=1):
            scores[doc_id] = scores.get(doc_id, 0.0) + 1.0 / (k + rank)
    return sorted(scores, key=lambda doc_id: scores[doc_id], reverse=True)
