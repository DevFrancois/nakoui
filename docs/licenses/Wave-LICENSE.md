# Wave source attribution

The spring equations and elastic limiting function in `CarouselWave.swift`
are adapted from the supplied Wave fork (`DevFrancois/Wave`, source commit
`cf5cfaa637a4fd0f7db7d4d37d3c1dce1768ead7`), originally created by Janum Trivedi.
Companion interactions follow Wave's interactive retargeting, velocity handoff, and
presentation-progress examples. The copied physics uses the carousel's existing
display clock. The stiffness/mass conversion is corrected for non-unit mass. The same
code drives selected-card pinches; pinch scale and rotation use a logarithmic soft limit
instead of Wave's rubber band, which keeps them below a ceiling.

Copyright (c) 2022 Janum Trivedi

Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify,
merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
