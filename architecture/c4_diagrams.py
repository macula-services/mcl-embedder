"""Generate mcl-embedder's two C4 diagrams into assets/.

Run:  python3 architecture/c4_diagrams.py

  c4-context.svg     Level 1: what the service talks to
  c4-components.svg  Level 2: what it is made of

Drawn from the code, never from a template: the callbacks in
mcl_embedder_service.erl, the request handling in serve_embed.erl, the
dependencies in rebar.config, the port and volumes in the Containerfile and
deploy/docker-compose.yml. When one of those changes, the diagram changes in
the same commit.

Colours are plain classes with a prefers-color-scheme: dark block, no CSS custom
properties (rsvg-convert renders those black), so the SVGs render the same on
GitHub, in IDE previews and through rsvg-convert. After a change, render each
(rsvg-convert -w 1400 assets/c4-context.svg -o /tmp/c.png) and look at it; keep
architecture/README.md's tables in step.
"""
import os
from xml.sax.saxutils import escape

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

SANS = '"Atkinson Hyperlegible", "Segoe UI", system-ui, -apple-system, Helvetica, Arial, sans-serif'
MONO = '"JetBrains Mono", ui-monospace, Menlo, Consolas, monospace'

# Element kinds, each (light fill, light stroke, dark fill, dark stroke).
KINDS = {
    "b-sys": ("#F5E9CC", "#A56F0A", "#3A2E13", "#E3AA3C"),   # in scope
    "b-per": ("#E3EBF2", "#3B5B7A", "#1D2A36", "#8EB4D8"),   # person
    "b-mac": ("#E6E4EE", "#5E5A78", "#26243A", "#A9A4C8"),   # Macula infrastructure
    "b-ext": ("#ECEFED", "#8A9791", "#1C2421", "#7D8B85"),   # external system
    "b-cmp": ("#FFFFFF", "#8A9791", "#171F1C", "#7D8B85"),   # component or container
}

STYLE = f"""<style>
.t-name {{ font-family: {SANS}; font-size: 15px; font-weight: 700; }}
.t-desc {{ font-family: {SANS}; font-size: 12.5px; }}
.t-rel {{ font-family: {SANS}; font-size: 11.5px; paint-order: stroke; stroke-width: 4px; stroke-linejoin: round; }}
.t-code {{ font-family: {MONO}; font-size: 13px; font-weight: 600; }}
.t-type {{ font-family: {MONO}; font-size: 11.5px; }}
.t-bound {{ font-family: {MONO}; font-size: 12px; font-weight: 600; }}
.t-leg {{ font-family: {SANS}; font-size: 12px; }}
.edge {{ fill: none; stroke-width: 1.25; }}
.edge-later {{ fill: none; stroke-width: 1.25; stroke-dasharray: 5 4; }}
.bg {{ fill: #FFFFFF; }}
""" + "".join(f".{k} {{ fill: {v[0]}; stroke: {v[1]}; stroke-width: {2 if k == 'b-sys' else 1.25}; }}\n" for k, v in KINDS.items()) + """\
.b-later { fill: none; stroke: #8A9791; stroke-width: 1.25; stroke-dasharray: 5 4; }
.bound { fill: none; stroke: #B3BDB8; stroke-width: 1; }
.head { fill: #3B5B7A; }
.t-name, .t-code { fill: #16201D; }
.t-type, .t-bound, .t-leg { fill: #66736E; }
.t-desc { fill: #34413C; }
.t-rel { fill: #66736E; stroke: #FFFFFF; }
.edge, .edge-later { stroke: #8A9791; }
.arrowhead { fill: #8A9791; }
@media (prefers-color-scheme: dark) {
.bg { fill: #171F1C; }
""" + "".join(f".{k} {{ fill: {v[2]}; stroke: {v[3]}; }}\n" for k, v in KINDS.items()) + """\
.b-later { stroke: #7D8B85; }
.bound { stroke: #4A5752; }
.head { fill: #8EB4D8; }
.t-name, .t-code { fill: #E6ECE9; }
.t-type, .t-bound, .t-leg { fill: #93A09A; }
.t-desc { fill: #C3CDC8; }
.t-rel { fill: #93A09A; stroke: #171F1C; }
.edge, .edge-later { stroke: #7D8B85; }
.arrowhead { fill: #7D8B85; }
}
</style>"""

DEFS = ('<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        'orient="auto-start-reverse"><path class="arrowhead" d="M0 0L10 5L0 10z"/></marker></defs>')

LEGEND = [("b-sys", "In scope"), ("b-per", "Person"), ("b-mac", "Macula infrastructure"),
          ("b-ext", "External system"), ("b-cmp", "Container or component")]
BOUNDARY = ("bound", "Boundary")


class Diagram:
    def __init__(self, name, title, w, h):
        self.name, self.title, self.w, self.h, self.parts = name, title, w, h, []

    def text(self, cls, x, y, s, anchor=None, rotate=None):
        a = f' text-anchor="{anchor}"' if anchor else ""
        r = f' transform="rotate({rotate} {x} {y})"' if rotate is not None else ""
        self.parts.append(f'<text class="{cls}" x="{x}" y="{y}"{a}{r}>{escape(s)}</text>')

    def box(self, cls, x, y, w, h, name, kind, desc, person=False, code=False):
        # A box that is too small for its own words renders as text on top of the
        # next box, which no test would catch and a reader would read as the
        # diagram saying something it does not. Fail here instead.
        need = 70 + 16 * max(len(desc) - 1, 0) + 18
        if h < need:
            raise ValueError(f"{self.name}: {name} needs height {need}, has {h}")
        for line in desc:
            if 16 + 6.2 * len(line) > w - 16:
                raise ValueError(f"{self.name}: {name}: '{line}' is wider than {w - 32}px")
        self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="10"/>')
        tx = x + 16
        if person:
            self.parts.append(f'<circle class="head" cx="{x + 26}" cy="{y + 24}" r="9"/>')
            tx = x + 44
        self.text("t-code" if code else "t-name", tx, y + 28, name)
        self.text("t-type", tx, y + 46, kind)
        for i, line in enumerate(desc):
            self.text("t-desc", x + 16, y + 70 + 16 * i, line)

    def bound(self, x, y, w, h, label):
        self.parts.append(f'<rect class="bound" x="{x}" y="{y}" width="{w}" height="{h}" rx="12"/>')
        self.text("t-bound", x + 16, y + 22, label)

    def edge(self, d, later=False):
        self.parts.append(f'<path class="{"edge-later" if later else "edge"}" d="{d}" marker-end="url(#a)"/>')

    def legend(self, y, boundary=True):
        x = 24
        for cls, label in LEGEND + ([BOUNDARY] if boundary else []):
            self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="22" height="14" rx="3"/>')
            self.text("t-leg", x + 30, y + 12, label)
            x += 34 + 6.6 * len(label)

    def write(self):
        svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" role="img" '
               f'aria-label="{escape(self.title)}">', f"<title>{escape(self.title)}</title>", STYLE, DEFS,
               f'<rect class="bg" x="0" y="0" width="{self.w}" height="{self.h}"/>'] + self.parts + ["</svg>", ""]
        with open(os.path.join(OUT, self.name), "w") as f:
            f.write("\n".join(svg))


def context():
    d = Diagram("c4-context.svg", "mcl-embedder system context", 1000, 660)
    d.box("b-per", 40, 30, 270, 120, "Mesh caller", "[Person]",
          ["A service or agent that cannot", "run the ONNX model itself;",
           "mcl-rag's embed provider is one"], person=True)
    d.box("b-per", 690, 30, 270, 120, "Service operator", "[Person]",
          ["Runs it on an AVX2 host and", "supplies the realm, the pinned",
           "seeds and the health port"], person=True)
    d.box("b-sys", 365, 186, 300, 152, "mcl-embedder", "[mcl_om mesh service]",
          ["mcl-embedder/embed is its own procedure.",
           "mcl_om adds info and get_limits, both",
           "open. capabilities/0 is the list.",
           "/health is on 8480; text in, vectors out"])
    d.box("b-mac", 40, 400, 270, 120, "macula-realm", "[Macula infrastructure]",
          ["Admits the node, and grants the", "D25 provider authorizations its",
           "org procedures need"])
    d.box("b-mac", 365, 400, 270, 120, "Macula stations, mesh DHT", "[Macula infrastructure]",
          ["The pinned seeds are its entry", "points (QUIC); the mesh DHT",
           "carries what it publishes"])
    d.edge("M175 150V168H420V186")
    d.text("t-rel", 183, 160, "calls mcl-embedder/embed")
    d.edge("M825 150V168H580V186")
    d.text("t-rel", 690, 160, "deploys; sets the env")
    d.edge("M420 338V370H175V400"); d.text("t-rel", 183, 362, "boot claim, provider grant")
    d.edge("M580 338V360H600V400"); d.text("t-rel", 608, 354, "advertises on the DHT")
    d.text("t-desc", 40, 566, "It talks to nothing outside the mesh at runtime: the ONNX model and its weights are")
    d.text("t-desc", 40, 584, "baked into the image at build time, so a container never downloads them.")
    d.legend(620, boundary=False)
    d.write()


def components():
    d = Diagram("c4-components.svg", "mcl-embedder components", 1000, 840)
    d.bound(16, 40, 968, 520, "mcl-embedder [Container]")
    d.box("b-cmp", 32, 70, 290, 120, "mcl_embedder_app", "[OTP application]",
          ["Application entry: start/2 calls", "mcl_om:boot/1 with this service",
           "module, which wires the mesh"], code=True)
    d.box("b-cmp", 346, 70, 290, 120, "mcl_embedder_service", "[mcl_om_service behaviour]",
          ["The six mcl_om_service callbacks,", "resolved by name. mcl-om adds the open",
           "info and get_limits beside them."], code=True)
    d.box("b-cmp", 660, 70, 308, 120, "mcl_embedder_sup", "[supervisor, one_for_one]",
          ["No children: the handler is started", "by mcl-om's capability registration,",
           "so the empty list is the honest shape"], code=True)
    d.box("b-sys", 32, 222, 290, 152, "serve_embed", "[macula_response handler]",
          ["handle_request/2: one text returns", "a vector, a list of texts a list of",
           "vectors. kind query or passage", "applies the e5 prefix; no text at",
           "all is refused as bad_request"], code=True)
    d.box("b-mac", 346, 222, 290, 152, "mcl_om", "[library, ~> 1.4]",
          ["boot/1: the node identity key,", "realm admission, a mesh pool, the",
           "capability registration and /health", "on MCL_HEALTH_PORT. Adds the open",
           "Org/info and Org/get_limits"], code=True)
    d.box("b-mac", 660, 222, 308, 152, "macula SDK", "[library, ~> 16.0, wire 1.0]",
          ["QUIC transport, the PQ handshake,", "RPC dispatch to a handler by name,",
           "and the signed records the mesh DHT", "holds"], code=True)
    d.box("b-mac", 32, 420, 624, 120, "mcl_embed", "[library, ~> 0.1.1, Rust NIF over ONNX]",
          ["embed/2, embed_query/2, embed_passage/2, embed_many/2 and default_model/0, over",
           "fastembed: multilingual-e5-small, 384 dimensions, loaded lazily on the first call.",
           "The image builds the real backend with CARGO_FEATURES=real-embed; tests use a stub"], code=True)
    d.box("b-ext", 660, 420, 308, 120, "AVX2 host", "[Host requirement]",
          ["The ONNX Runtime SIGILLs on a CPU", "without AVX2, so the box running",
           "this image must have it"])
    d.box("b-ext", 40, 620, 920, 120, "Deploy environment", "[environment, from the host or the compose file]",
          ["MCL_REALM and MCL_REALM_KEY admit the node; MACULA_STATION_SEEDS and MACULA_STATION_NODE_IDS",
           "are the pinned dial; MCL_HEALTH_PORT is 8480; MCL_SERVICE_NAME and MCL_BOX label the claim. mcl_embed",
           "reads MCL_EMBED_MODEL_DIR (/models) on the first call. The identity key lives on the named volume /etc/mcl/secrets"])
    d.edge("M322 110H346"); d.text("t-rel", 334, 102, "boots", anchor="middle")
    d.edge("M636 130H660"); d.text("t-rel", 648, 122, "starts", anchor="middle")
    d.edge("M346 150H334V290H322"); d.text("t-rel", 340, 220, "declares in capabilities/0", anchor="middle", rotate=-90)
    d.edge("M300 222V200H644V300H660"); d.text("t-rel", 590, 212, "replies through", anchor="middle")
    d.edge("M180 374V420"); d.text("t-rel", 188, 414, "embeds with")
    d.edge("M340 620V540"); d.text("t-rel", 348, 576, "MCL_EMBED_MODEL_DIR,"); d.text("t-rel", 348, 592, "read on the first call")
    d.edge("M40 666H24V400H500V374"); d.text("t-rel", 300, 394, "read at boot")
    d.text("t-desc", 40, 752, "config/sys.config.src fixes the org, mcl-embedder, which prefixes procedure names, and pins the")
    d.text("t-desc", 40, 770, "realm key: a boot with a malformed term is refused. The model loads on the first call, so")
    d.text("t-desc", 40, 788, "/health never probes it, and deploy/docker-compose.yml runs the container on the host network.")
    d.legend(806)
    d.write()


if __name__ == "__main__":
    for make in (context, components):
        make()
