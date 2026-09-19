import pandas as pd

from src.split import group_train_test_split


def make_panel(n_states: int = 10, rows_per_state: int = 4) -> pd.DataFrame:
    states = [f"State{i}" for i in range(n_states)]
    return pd.DataFrame(
        {
            "state": [s for s in states for _ in range(rows_per_state)],
            "row_id": list(range(n_states * rows_per_state)),
        }
    )


def test_no_state_appears_on_both_sides():
    panel = make_panel(10)
    train, test = group_train_test_split(panel, test_frac=0.3, seed=1)

    assert set(train["state"]).isdisjoint(set(test["state"]))
    assert len(train) + len(test) == len(panel)


def test_test_fraction_is_applied_to_the_group_count_not_row_count():
    panel = make_panel(10, rows_per_state=4)
    train, test = group_train_test_split(panel, test_frac=0.3, seed=1)

    assert test["state"].nunique() == 3
    assert train["state"].nunique() == 7


def test_same_seed_is_deterministic():
    panel = make_panel(10)
    train_a, test_a = group_train_test_split(panel, test_frac=0.3, seed=5)
    train_b, test_b = group_train_test_split(panel, test_frac=0.3, seed=5)

    assert set(test_a["state"]) == set(test_b["state"])
