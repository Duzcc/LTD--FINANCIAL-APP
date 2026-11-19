from __future__ import annotations

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import FeatureUnion, Pipeline

from app.nlp.text import model_text


def text_features() -> FeatureUnion:
    return FeatureUnion(
        [
            (
                "word",
                TfidfVectorizer(
                    preprocessor=model_text,
                    analyzer="word",
                    ngram_range=(1, 2),
                    min_df=1,
                    sublinear_tf=True,
                    token_pattern=r"(?u)\b\w+\b",
                ),
            ),
            (
                "char",
                TfidfVectorizer(
                    preprocessor=model_text,
                    analyzer="char_wb",
                    ngram_range=(2, 5),
                    min_df=2,
                    sublinear_tf=True,
                    max_features=60000,
                ),
            ),
        ]
    )


def text_classifier(c: float = 8.0) -> Pipeline:
    return Pipeline(
        [
            ("features", text_features()),
            ("clf", LogisticRegression(C=c, max_iter=3000, class_weight="balanced")),
        ]
    )
