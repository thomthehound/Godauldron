# Lee Perry-Smith scanned reference head

The optional `scenes/showcase/scanned_reference_head.tscn` provides a photographic 3D head scan for scalp and hair-silhouette inspection, separately from the MakeHuman full-body test fixture.

## Source and attribution

**Lee Perry-Smith / Infinite Realities**, *Infinite, 3D Head Scan*. Licensed under **Creative Commons Attribution 3.0 Unported (CC BY 3.0)**. Based on a work at www.triplegangers.com.

Original redistributable files in the [three.js example library](https://github.com/mrdoob/three.js/tree/dev/examples/models/gltf/LeePerrySmith):

- `LeePerrySmith.glb` → `assets/showcase/lee_perry_smith.glb`
- `Map-COL.jpg` → `assets/showcase/lee_perry_smith_color.jpg`
- `Infinite-Level_02_Tangent_SmoothUV.jpg` → `assets/showcase/lee_perry_smith_normal.jpg`
- [Upstream license notice](https://github.com/mrdoob/three.js/blob/dev/examples/models/gltf/LeePerrySmith/LeePerrySmith_License.txt)

These original files are bundled unmodified. The Godot scene supplies external material settings, lighting, scene scaling, and camera composition.

## Reference role and limits

The bare head avoids the MakeHuman sample's hairstyle obscuring the scalp. The source mesh's object-space X/Y/Z extents are approximately 8.55/7.95/5.18 arbitrary units. The scene uses an editorial scale factor of 0.03 (about 25.7 cm wide), **not a scan-provided physical measurement**.

The supplied image maps are for presentation; they do not supply a collision-ready scalp mesh, UV-stable follicles, attachment transforms, or verified real-world dimensions. Actual LoxFX groom placement, attachment, solver, and rendering belong to the provider.

The scene inherits Godauldron's ordinary camera/light stage and deterministic, adjustable translation. Its camera and lighting are deliberately separate from the MakeHuman baseline so both candidates can be evaluated without changing the underlying host.

## Visual acceptance

The graphics-backed `portrait-visual-capture` CI job renders still and translated images from both subjects, plus profile and rear views of the scanned head. Assess frontal and angled silhouette, visible scalp area, texture/material quality, lighting, motion framing, and eventual groom/root correspondence using real screenshots. Do not substitute glTF import success or image generation for this review.
