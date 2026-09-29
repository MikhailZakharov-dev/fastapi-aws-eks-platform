# Mutable tag: "roll back to yesterday's latest" cannot be done

- **Symptom:** after a rebuild under the same tag `talk-booking:latest` the old image
  became unreachable: `docker images f13cd…` returns nothing. Which code ran yesterday
  cannot be recovered from the tag name.
- **Signal:** `docker images -a talk-booking` before and after the rebuild. The tag moved
  `f13cdf5e2d54 → 4771a8b5bb7e`, the old ID is left nameless and hidden (containerd
  store). In ECR the second push of `:latest` was rejected:
  `The image tag 'latest' … cannot be overwritten because the tag is immutable`,
  while `Layer already exists` shows the layers were accepted and deduplicated.
- **Cause:** a tag is a mutable pointer in the registry's name table, not a property of
  the image. A rebuild or a push silently moves the name to a new digest, and the
  registry keeps no history of tags. The content does not die. The address does.
- **Fix:** tag = `$CI_COMMIT_SHA` (immutable by construction: git log and registry are
  stitched together, a rollback is a pull of the old SHA), plus ECR
  `image_tag_mutability = IMMUTABLE` to protect the name table on the storage side.
- **Prevention:** anything that gets deployed is always addressed by an immutable name
  (a SHA tag or a digest). `:latest` is acceptable only where nobody will ask "what ran
  yesterday" (local development, one-off use). The lifecycle policy counts junk pushes
  too: a leaked push key can wipe out the rollback history (keep-4).
