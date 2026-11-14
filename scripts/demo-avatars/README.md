# Demo avatars

Profile photos for the seeded demo runners (`../demo_community.py`), uploaded through Profile's own
photo flow. One PNG per runner slug; Ray has none, so the live photo upload can be shown on him.

Generated with [DiceBear](https://www.dicebear.com) 9.x, style **Notionists** by Zoish, licensed
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Illustrations, not real people.

Regenerate one (seed is `<slug>-runner`):

```sh
curl -o nok.png "https://api.dicebear.com/9.x/notionists/png?seed=nok-runner&size=256&backgroundColor=c8ff3d"
```
