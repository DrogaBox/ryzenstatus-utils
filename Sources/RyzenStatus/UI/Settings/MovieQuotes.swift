// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

enum MovieQuotes {
    static let quotes: [String] = [
        "I'll be back. — The Terminator (1984)",
        "May the Force be with you. — Star Wars (1977)",
        "I see dead people. — The Sixth Sense (1999)",
        "Follow the white rabbit. — The Matrix (1999)",
        "Houston, we have a problem. — Apollo 13 (1995)",
        "Hasta la vista, baby. — Terminator 2 (1991)",
        "Say hello to my little friend! — Scarface (1983)",
        "Why so serious? — The Dark Knight (2008)",
        "You're gonna need a bigger boat. — Jaws (1975)",
        "Keep your friends close, but your enemies closer. — The Godfather Part II (1974)",
        "There's no place like home. — The Wizard of Oz (1939)",
        "Show me the money! — Jerry Maguire (1996)",
        "You can't handle the truth! — A Few Good Men (1992)",
        "My precious. — The Lord of the Rings: The Two Towers (2002)",
        "Bond. James Bond. — Dr. No (1962)",
        "To infinity and beyond! — Toy Story (1995)",
        "E.T. phone home. — E.T. the Extra-Terrestrial (1982)",
        "Frankly, my dear, I don't give a damn. — Gone with the Wind (1939)",
        "I'm the king of the world! — Titanic (1997)",
        "Here's Johnny! — The Shining (1980)",
        "Fasten your seatbelts. It's going to be a bumpy night. — All About Eve (1950)",
        "What we've got here is failure to communicate. — Cool Hand Luke (1967)",
        "Go ahead, make my day. — Sudden Impact (1983)",
        "I love the smell of napalm in the morning. — Apocalypse Now (1979)",
        "The first rule of Fight Club is: You do not talk about Fight Club. — Fight Club (1999)",
        "I'm walking here! I'm walking here! — Midnight Cowboy (1969)",
        "You talking to me? — Taxi Driver (1976)",
        "Great Scott! — Back to the Future (1985)",
        "Run, Forrest, run! — Forrest Gump (1994)",
        "Welcome to Jurassic Park. — Jurassic Park (1993)",
        "Live long and prosper. — Star Trek (1979)",
        "Roads? Where we're going, we don't need roads. — Back to the Future (1985)",
        "Get to the chopper! — Predator (1987)",
        "Whom do you serve? — The Lord of the Rings (2001)",
        "Execute Order 66. — Star Wars: Revenge of the Sith (2005)",
        "Burn the witch! — Monty Python and the Holy Grail (1975)"
    ]

    static func randomQuote(excluding current: String? = nil) -> String {
        let available = quotes.filter { $0 != current }
        return available.randomElement() ?? quotes.randomElement() ?? "Follow the white rabbit."
    }
}
