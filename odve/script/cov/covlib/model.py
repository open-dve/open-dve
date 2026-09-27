"""In-memory coverage model shared by the parser (SystemVerilog covergroup
subset), the YAML form, the generator and the reports. Standard library only.

Values are plain Python ints; `$` in a range is resolved by the parser to the
sample argument's type bounds, so the model never carries it."""
from dataclasses import dataclass, field
from typing import List, Optional, Tuple


@dataclass
class Arg:
    """One argument of `with function sample(...)`."""
    type: str            # as written, e.g. "int", "bit [3:0]"
    name: str
    width: int           # bits
    signed: bool

    @property
    def min(self):
        return -(1 << (self.width - 1)) if self.signed else 0

    @property
    def max(self):
        return (1 << (self.width - 1)) - 1 if self.signed else (1 << self.width) - 1


@dataclass
class Bin:
    """One bin of a coverpoint. Exactly one of ranges / wild / trans /
    default describes what it matches."""
    name: str
    kind: str = "bin"                                   # bin | ignore | illegal
    ranges: List[Tuple[int, int]] = field(default_factory=list)   # inclusive [lo, hi]
    wild: List[Tuple[int, int]] = field(default_factory=list)     # (value, care-mask) pairs
    trans: List[List[int]] = field(default_factory=list)          # value sequences, e.g. [[1, 2, 3]]
    default: bool = False

    @property
    def is_coverage(self):
        return self.kind == "bin"


@dataclass
class Point:
    name: str
    arg: str                              # sample argument it covers
    bins: List[Bin]
    iff: Optional[Tuple[str, bool]] = None   # (argument, negated)
    at_least: Optional[int] = None
    line: int = 0

    @property
    def coverage_bins(self):
        return [b for b in self.bins if b.is_coverage]


@dataclass
class Filter:
    """ignore_bins / illegal_bins of a cross, as a boolean expression over
    binsof() terms: ('binsof', point, bin-or-None) | ('not', e) |
    ('and', e1, e2) | ('or', e1, e2)."""
    name: str
    kind: str            # ignore | illegal
    expr: tuple


@dataclass
class Cross:
    name: str
    points: List[str]
    filters: List[Filter] = field(default_factory=list)
    at_least: Optional[int] = None
    line: int = 0


@dataclass
class Group:
    """One covergroup. `unsupported` set means the group was recognised but
    not understood: the generator emits a stub and a warning for it."""
    name: str
    args: List[Arg] = field(default_factory=list)
    points: List[Point] = field(default_factory=list)
    crosses: List[Cross] = field(default_factory=list)
    at_least: Optional[int] = None
    weight: int = 1
    file: str = ""
    line: int = 0
    text: str = ""
    unsupported: Optional[str] = None

    def point(self, name):
        for p in self.points:
            if p.name == name:
                return p
        return None


@dataclass
class Model:
    groups: List[Group] = field(default_factory=list)
    created: List[str] = field(default_factory=list)    # names seen in `odve_cov_create(...)
    sampled: List[str] = field(default_factory=list)    # names seen in `odve_cov_sample(...)

    def group(self, name):
        for g in self.groups:
            if g.name == name:
                return g
        return None
