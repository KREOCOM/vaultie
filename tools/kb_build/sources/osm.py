"""OpenStreetMap brand acquisition — OFFLINE, DISABLED BY DEFAULT.

LICENSING (why this is off by default):
  OSM data is licensed under the Open Database License (ODbL 1.0). Unlike
  Wikidata (CC0), ODbL carries attribution AND share-alike obligations on any
  "Derivative Database". Bundling OSM-derived brand records into the shipped
  merchant KB artifact would make that artifact a Derivative Database and pull
  those obligations onto Vaultie's distributed app.

  Until that obligation is explicitly reviewed and accepted (attribution surface
  + share-alike handling of the artifact), OSM is NOT compiled into the shipped
  artifact. This module documents the extraction path so it can be enabled
  deliberately, not accidentally.

EXTRACTION PATH (when enabled):
  Query Overpass for nodes/ways with `brand`/`operator` + `brand:wikidata` tags
  in the target countries, keep only records that carry `brand:wikidata` (so each
  OSM record links to a CC0 Wikidata entity and can be merged as *corroboration*
  of an existing Wikidata brand rather than as new ODbL-only data). Records with
  no `brand:wikidata` link are dropped, which keeps the shipped artifact free of
  ODbL-only content.

Runtime never imports this module.
"""

ENABLED = False  # flip only after ODbL review; see module docstring.


def fetch(refresh=False):
    if not ENABLED:
        return []
    raise NotImplementedError(
        "OSM acquisition is gated off pending explicit ODbL review. "
        "Enable only with attribution + share-alike handling in place.")
