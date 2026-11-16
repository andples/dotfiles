// classic (the default): looks like a LaTeX article. Computer Modern, numbered headings,
// plain theorems.
// Every template has the same functions, so switching (`notes template NAME`) never
// means editing notes:
//   #show: note.with(title: "…", date: "…")
//   #definition[…]  #theorem[…]  #lemma[…]  #proof[…]  #example[…]  #remark[…]
//   each takes an optional name: #theorem(name: "Pythagoras")[…]

#let _num = counter("note-env")

#let note(title: none, date: none, body) = {
  set document(title: title)
  set page(paper: "a4", margin: 2.5cm, numbering: "1")
  set text(font: "New Computer Modern", size: 11pt)
  set par(justify: true, leading: 0.62em)
  set heading(numbering: "1.1")
  show heading: set block(above: 1.4em, below: 0.8em)
  set math.equation(numbering: "(1)")
  show raw: set text(font: "DejaVu Sans Mono", size: 9pt)
  if title != none {
    align(center, {
      text(18pt, title)
      if date != none { linebreak(); v(0.2em); text(10pt, date) }
    })
    v(1.5em)
  }
  body
}

#let _env(kind, name, body, numbered: true, italic: false) = {
  if numbered { _num.step() }
  block(above: 1.2em, below: 1.2em, context {
    strong(kind)
    if numbered { strong[ #_num.display()] }
    if name != none [ (#name)]
    strong[.]
    h(0.4em)
    if italic { emph(body) } else { body }
  })
}

#let definition(name: none, body) = _env("Definition", name, body)
#let theorem(name: none, body) = _env("Theorem", name, body, italic: true)
#let lemma(name: none, body) = _env("Lemma", name, body, italic: true)
#let example(name: none, body) = _env("Example", name, body, numbered: false)
#let remark(name: none, body) = _env("Remark", name, body, numbered: false)
#let proof(body) = block(above: 0.8em, below: 1.2em)[
  _Proof._ #h(0.3em) #body #h(1fr) $square$
]
