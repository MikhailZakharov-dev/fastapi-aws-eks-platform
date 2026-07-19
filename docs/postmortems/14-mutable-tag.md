# Mutable tag: «откатись на вчерашний latest» невыполним

- **Symptom:** после пересборки под тем же тегом `talk-booking:latest` старый
  образ стал недостижим: `docker images f13cd…` — пусто; «какой код бежал вчера»
  по имени тега восстановить нельзя.
- **Signal:** `docker images -a talk-booking` до/после пересборки — тег
  перевесился `f13cdf5e2d54 → 4771a8b5bb7e`, старый ID безымянный и скрыт
  (containerd-стор); в ECR второй push `:latest` отвергнут:
  `The image tag 'latest' … cannot be overwritten because the tag is immutable`,
  при этом `Layer already exists` — слои приняты/дедуплицированы.
- **Cause:** тег — mutable-указатель в таблице имён реестра, а не свойство
  образа. Пересборка/пуш молча перевешивает имя на новый digest; истории тегов
  реестр не ведёт. Умирает не содержимое — умирает адрес.
- **Fix:** тег = `$CI_COMMIT_SHA` (immutable по построению: git log ↔ registry
  сшиты, откат = pull старого SHA) + ECR `image_tag_mutability = IMMUTABLE`
  как защита таблицы имён на стороне хранилища.
- **Prevention:** деплоимое всегда адресуется immutable-именем (SHA-тег или
  digest); `:latest` допустим только там, где не нужен ответ «что бежало вчера»
  (локальная разработка, одноразовое). Lifecycle-политика считает и мусорные
  пуши — утёкший push-ключ выбивает историю откатов (keep-4).
