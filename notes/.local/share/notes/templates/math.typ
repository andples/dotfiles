// math: for maths notes. Libertinus, a blue accent, tinted boxes for definitions and
// theorems, numbered equations, running header.
// Same functions as every template (see classic.typ), so switching never means editing notes.

#let accent = rgb("#2563a8")
#let _num = counter("note-env")

#let note(title: none, date: none, body) = {
  set document(title: title)
  set page(
    paper: "a4",
    margin: (x: 2.3cm, top: 2.4cm, bottom: 2.2cm),
    header: context if here().page() > 1 {
      set text(8.5pt, fill: luma(120))
      smallcaps(title)
      h(1fr)
      counter(page).display()
    },
  )
  set text(font: "Libertinus Serif", size: 11.5pt)
  set par(justify: true, leading: 0.65em)
  set heading(numbering: "1.1")
  show heading: it => block(above: 1.6em, below: 0.8em, text(fill: accent, it))
  show heading.where(level: 1): it => block(above: 1.8em, below: 0.9em, {
    text(fill: accent, size: 15pt, it)
    v(-0.5em)
    line(length: 100%, stroke: 0.5pt + accent.lighten(60%))
  })
  set math.equation(numbering: "(1)")
  show raw: set text(font: "DejaVu Sans Mono", size: 9pt)
  show raw.where(block: true): block.with(fill: luma(246), inset: 8pt, radius: 3pt, width: 100%)
  show link: set text(fill: accent)
  set list(marker: (text(fill: accent)[•], text(fill: accent)[‣], text(fill: accent)[–]))
  set enum(numbering: n => text(fill: accent)[#n.])
  if title != none {
    text(24pt, weight: "bold", fill: accent, title)
    if date != none { linebreak(); text(10pt, fill: luma(110), date) }
    v(1.2em)
  }
  body
}

#let _box(kind, name, body, color, numbered: true) = {
  if numbered { _num.step() }
  block(
    width: 100%,
    above: 1.1em,
    below: 1.1em,
    inset: (x: 10pt, y: 8pt),
    fill: color.lighten(92%),
    stroke: (left: 2.5pt + color),
    radius: (right: 3pt),
    context {
      text(fill: color, weight: "bold", {
        kind
        if numbered [ #_num.display()]
      })
      if name != none [ #h(0.2em) _#name _]
      h(0.5em)
      body
    },
  )
}

#let definition(name: none, body) = _box("Definition", name, body, accent)
#let theorem(name: none, body) = _box("Theorem", name, body, rgb("#8a3ab9"))
#let lemma(name: none, body) = _box("Lemma", name, body, rgb("#8a3ab9"))
#let example(name: none, body) = _box("Example", name, body, rgb("#2e8b57"), numbered: false)
#let remark(name: none, body) = _box("Remark", name, body, rgb("#b07a1f"), numbered: false)
#let proof(body) = block(above: 0.6em, below: 1.1em, inset: (left: 12pt))[
  #text(fill: luma(90), style: "italic")[Proof.] #h(0.3em) #body #h(1fr) $square$
]
