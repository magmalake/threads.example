# A temporary dies at the end of the statement; there is nothing to share.
# expect-error: cannot be converted from 'Totals' to ref 'Totals'
from origins import Totals, task
from threads import parallel_for


def main() raises:
    parallel_for[task](1000, Totals(0))
