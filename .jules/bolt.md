## 2024-05-24 - Cache CharacterSet in hot paths
**Learning:** Instantiating `CharacterSet(charactersIn:)` in Swift has noticeable overhead due to string parsing and memory allocation. When used inside functions that run on every render tick (like color normalization in a menu bar renderer), this adds unnecessary CPU load.
**Action:** Extract `CharacterSet` instances into `static let` properties when they are used inside hot paths, especially render loops.
