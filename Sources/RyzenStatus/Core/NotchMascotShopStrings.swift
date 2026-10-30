// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The words of the shop: the twenty-four curiosities with the gag each one
/// plays, and what the stall says. English and Spanish are worded; the
/// other languages read the English until they are translated.
struct NotchMascotShopStrings {
    /// In the order of `NotchMascotAccessory.shopItems`.
    let items: [String]
    let gags: [String]
    let rarities: [String]
    let title: String
    let buy: String
    let owned: String
    let reroll: String
    let soldOut: String
    let tooPoor: String
    let close: String
    let gold: String
    /// "Shop · 120" on a thing in the wardrobe not bought yet.
    let shopTag: String
    /// Under the stall in Settings: what it sells and where the gold comes from.
    let hint: String

    func name(of accessory: NotchMascotAccessory) -> String? {
        guard let index = NotchMascotAccessory.shopItems.firstIndex(of: accessory) else { return nil }
        return items[index]
    }

    /// The curiosity's line, or a toy's, in the app's language.
    func gag(of accessory: NotchMascotAccessory) -> String? {
        guard let index = NotchMascotAccessory.shopItems.firstIndex(of: accessory) else {
            return FeatureStrings.notchMascotToys(L10n.shared.language).gag(of: accessory)
        }
        return gags[index]
    }

    func rarity(_ rarity: NotchMascotRarity) -> String { rarities[rarity.rawValue] }

    static let itemCount = 24

    var isComplete: Bool {
        items.count == Self.itemCount && gags.count == Self.itemCount && rarities.count == NotchMascotRarity.allCases.count
    }
}

extension FeatureStrings {
    static func notchMascotShop(_ language: AppLanguage) -> NotchMascotShopStrings {
        language == .es ? spanishShop : englishShop
    }

    private static let englishShop = NotchMascotShopStrings(
        items: ["Rubber Duck", "Banana Peel", "Clown Nose", "Cream Pie", "Whoopee Cushion", "Fake Mustache",
                "Traffic Cone", "Piggy Bank", "Alarm Clock", "Storm Cloud", "Wilted Flower", "Lonely Balloon",
                "Teddy Bear", "Tissue Box", "Broken Locket", "Tinfoil Hat", "Magic Mushroom", "Disco Ball",
                "Alien Antenna", "Dynamite", "Mimic Chest", "Crystal Skull", "Cursed Mask", "Unicorn Horn"],
        gags: ["Squeaks, and the other jumps.", "Thrown: the other slips.", "Honk! Both laugh.",
               "Flies, then splat.", "A rude noise; a blush.", "The other turns detective.",
               "A hat, or a megaphone.", "Shake it: coins rain.", "Rings; the other wakes up.",
               "Its own rain; shared umbrella.", "Offered, and petals fall.", "Floats away; both watch it go.",
               "A hug when it is needed.", "For the one who cries.", "Splits; a potion mends it.",
               "Antennas and sparks.", "Grows, shrinks, confetti.", "Both dance disco.",
               "A tractor beam abduction.", "Fuse, boom, soot.", "Bites, then spits coins.",
               "Ghost smoke and a scare.", "Possessed: a tornado duel.", "A rainbow of sparks."],
        rarities: ["Common", "Uncommon", "Rare", "Legendary"],
        title: "Shop", buy: "Buy", owned: "Owned", reroll: "New stock", soldOut: "Sold out: you own it all",
        tooPoor: "Not enough gold", close: "Close", gold: "Gold", shopTag: "Shop",
        hint: "Four things at a time, at random; the rarer, the wilder their combos. Gold comes from pats, fruit, snacks, bosses, new combos and each day together.")

    private static let spanishShop = NotchMascotShopStrings(
        items: ["Pato de goma", "Cáscara de plátano", "Nariz de payaso", "Tarta de crema", "Cojín pedorro",
                "Bigote falso", "Cono de tráfico", "Hucha", "Despertador", "Nube de tormenta", "Flor marchita",
                "Globo solitario", "Osito de peluche", "Caja de pañuelos", "Relicario roto", "Gorro de aluminio",
                "Seta mágica", "Bola disco", "Antena alienígena", "Dinamita", "Cofre mímico", "Calavera de cristal",
                "Máscara maldita", "Cuerno de unicornio"],
        gags: ["Chirría y el otro salta.", "Lanzada: el otro resbala.", "¡Pip! Se ríen los dos.",
               "Vuela y hace splat.", "Un ruido feo; un sonrojo.", "El otro se vuelve detective.",
               "Sombrero o megáfono.", "Sacúdela: llueven monedas.", "Suena y el otro despierta.",
               "Su propia lluvia; paraguas compartido.", "Se ofrece y caen pétalos.", "Se escapa; lo miran irse.",
               "Un abrazo cuando hace falta.", "Para el que llora.", "Se parte; una poción lo repara.",
               "Antenas y chispazos.", "Crece, encoge, confeti.", "Los dos bailan disco.",
               "Abducción con rayo tractor.", "Mecha, boom, hollín.", "Muerde y escupe monedas.",
               "Humo fantasma y un susto.", "Poseído: duelo de tornados.", "Un arcoíris de chispas."],
        rarities: ["Común", "Poco común", "Raro", "Legendario"],
        title: "Tienda", buy: "Comprar", owned: "Tuyo", reroll: "Nuevo escaparate", soldOut: "Agotado: ya lo tienes todo",
        tooPoor: "Falta oro", close: "Cerrar", gold: "Oro", shopTag: "Tienda",
        hint: "Cuatro cosas cada vez, al azar; cuanto más raras, más locos sus combos. El oro sale de mimarlo, la fruta, la comida, los jefes, los combos nuevos y cada día juntos.")
}

/// The words of the sound settings, in English and Spanish; the other
/// languages read the English until they are translated.
struct NotchMascotSoundStrings {
    let title: String
    let toggle: String
    let toggleHint: String
    let volume: String
    let test: String
}

extension FeatureStrings {
    static func notchMascotSound(_ language: AppLanguage) -> NotchMascotSoundStrings {
        language == .es
            ? NotchMascotSoundStrings(title: "Sonido", toggle: "Sonidos de los compañeros",
                                      toggleHint: "Efectos al jugar, con el sonido repartido según dónde ocurre: izquierda, centro o derecha de la pantalla.",
                                      volume: "Volumen", test: "Probar")
            : NotchMascotSoundStrings(title: "Sound", toggle: "Companion sounds",
                                      toggleHint: "Effects while they play, panned to where it happens on screen: left, middle or right.",
                                      volume: "Volume", test: "Test")
    }
}
