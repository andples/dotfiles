// The note `notes template --preview` renders with each template, so they can be compared.
// It also shows what a note looks like: notes start with these two lines.
#import "template.typ": *
#show: note.with(title: "Linear maps", date: "2026-11-17")

= Definitions

Throughout, $V$ and $W$ are vector spaces over a field $FF$, and $dim V = n$.

#definition(name: "Linear map")[
  A function $T: V -> W$ is *linear* if for all $u, v in V$ and $lambda in FF$,
  $ T(u + v) = T(u) + T(v) quad "and" quad T(lambda v) = lambda T(v). $
]

#definition[
  The *kernel* of $T$ is $ker T = {v in V : T(v) = 0}$ and its *image* is
  $im T = {T(v) : v in V}$.
]

#example[
  Differentiation $D: cal(P)_n -> cal(P)_(n-1)$, $p |-> p'$, is linear, with
  $ker D$ the constant polynomials.
]

= Rank–nullity

#theorem(name: "Rank–nullity")[
  If $V$ is finite-dimensional and $T: V -> W$ is linear, then
  $ dim V = dim ker T + dim im T. $
]

#proof[
  Extend a basis $(u_1, ..., u_k)$ of $ker T$ to a basis $(u_1, ..., u_k, v_1, ..., v_m)$
  of $V$. Then $(T v_1, ..., T v_m)$ spans $im T$, and if $sum_i a_i T v_i = 0$ then
  $sum_i a_i v_i in ker T$, which forces every $a_i = 0$. So $dim im T = m = n - k$.
]

#lemma[
  $T$ is injective if and only if $ker T = {0}$.
]

#remark[
  For a square matrix $A in FF^(n times n)$ this gives
  $ A "invertible" <==> det A != 0 <==> "rank" A = n. $
]

== A computation

$
  A = mat(1, 2; 3, 4), quad
  det A = 1 dot 4 - 2 dot 3 = -2, quad
  A^(-1) = 1/(-2) mat(4, -2; -3, 1).
$

$
  integral_0^infinity e^(-x^2) dif x = sqrt(pi) / 2, quad
  sum_(k=1)^infinity 1/k^2 = pi^2 / 6.
$

- Linear maps are determined by where they send a basis.
- Composition corresponds to matrix multiplication.

```python
import numpy as np
np.linalg.matrix_rank(np.array([[1, 2], [3, 4]]))  # 2
```

= Paper: Attention Is All You Need

_Vaswani et al., NeurIPS 2017_ · read 2026-11-17

== Summary
- Replaces recurrence with *self-attention* only: the Transformer.
- Trains faster than RNNs, since every position is processed in parallel.
- New state of the art on WMT'14 English–German translation (28.4 BLEU).

== Key ideas
- Scaled dot-product attention:
  $ "Attention"(Q, K, V) = "softmax"((Q K^top) / sqrt(d_k)) V $
  - The $sqrt(d_k)$ stops large dot products saturating the softmax.
  - Cost is $O(n^2 d)$ in the sequence length $n$.
- Multi-head attention: $h = 8$ heads, each attending in a smaller subspace.
- Positional encodings (sinusoids), since attention ignores order.

== Thoughts
- Strong: simple architecture, and the ablations are clear.
- Weak: the quadratic cost in $n$ limits long inputs.
- Questions
  + Why sinusoids rather than learned positions? (They report both work about equally.)
  + How does it relate to graph neural networks?
