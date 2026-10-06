"""
train_rf.py — الموديل الأول: Random Forest (خط الأساس)
-------------------------------------------------------
كل take (100 قراءة × 11 قناة) بيتلخص في 77 رقم (متوسط، تذبذب، ...)
وبعدين Random Forest يتعلم منهم.

الاختبار: Leave-One-Person-Out
  كل مرة نشيل شخص كامل من التدريب ونختبر عليه.
  ده الرقم الحقيقي: الموديل بيشتغل على إيد عمره ما شافها.
"""
import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, confusion_matrix

from common import LABELS, context_windows, features, load_takes, transition_windows


def top_confusions(y_true, y_pred, n=5):
    """أكتر إشارات الموديل بيلخبط بينها"""
    cm = pd.DataFrame(confusion_matrix(y_true, y_pred, labels=LABELS), index=LABELS, columns=LABELS)
    pairs = [(cm.loc[a, b], a, b) for a in LABELS for b in LABELS if a != b and cm.loc[a, b] > 0]
    return sorted(pairs, reverse=True)[:n]


def fit(X, y, persons):
    """بيدرّب على الـ takes الأصلية + نسخ مزاحة زي اللي هتيجي في التوقع الحي"""
    Xc, yc = context_windows(X, y, persons)
    Xt, yt = transition_windows(X, y, persons)          # نوافذ الانتقال من إشارة لإشارة
    clf = RandomForestClassifier(n_estimators=300, random_state=0, n_jobs=-1)
    return clf.fit(features(np.concatenate([X, Xc, Xt])), np.concatenate([y, yc, yt]))


def main():
    X, y, persons = load_takes("data")
    F = features(X)
    print(f"{len(y)} take | {len(set(persons))} أشخاص | {F.shape[1]} feature لكل take\n")

    all_true, all_pred = [], []
    print("الاختبار على شخص الموديل مشافوش:")
    for p in sorted(set(persons)):
        test = persons == p
        clf = fit(X[~test], y[~test], persons[~test])
        pred = clf.predict(F[test])
        all_true += list(y[test])
        all_pred += list(pred)
        print(f"  {p}: {accuracy_score(y[test], pred) * 100:5.1f}%")

    acc = accuracy_score(all_true, all_pred) * 100
    print(f"\nالدقة على أشخاص جداد (Random Forest): {acc:.1f}%")
    print("أكتر لخبطة:")
    for count, a, b in top_confusions(all_true, all_pred):
        print(f"  {a:9s} اتقرت {b:9s} {count} مرة")

    # الموديل النهائي بيتدرب على كل الناس
    clf = fit(X, y, persons)
    clf.n_jobs = 1          # التوقع الحي take واحد كل مرة: thread واحد أسرع بكتير
    joblib.dump(clf, "ishara_rf.joblib", compress=3)   # من غير ضغط الملف بيوصل لـ 190 ميجا
    print("\nاتحفظ في ishara_rf.joblib")
    return acc


if __name__ == "__main__":
    main()
