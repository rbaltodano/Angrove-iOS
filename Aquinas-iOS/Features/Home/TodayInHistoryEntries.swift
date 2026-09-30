//
//  TodayInHistoryEntries.swift
//  Aquinas-iOS
//

import Foundation

/// A small, hand-curated Today in History entry. Historical descriptions came from the retired
/// development backend; display titles are short headlines. Entries are never model-generated.
struct TodayInHistoryEntry: Equatable {
    /// "MM-DD"
    let date: String
    let title: String
    let description: String
    let relatedEntity: String
}

/// Deliberately not full 365-day coverage. A day with no entry means the Home section is simply
/// omitted; callers must never fabricate a placeholder for a missing date.
enum TodayInHistoryCatalog {
    static func entry(for date: Date, calendar: Calendar = .current) -> TodayInHistoryEntry? {
        let components = calendar.dateComponents([.month, .day], from: date)
        let key = String(format: "%02d-%02d", components.month ?? 0, components.day ?? 0)
        return byDate[key]
    }

    private static let byDate: [String: TodayInHistoryEntry] = Dictionary(
        entries.map { ($0.date, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    /// Match an existing conversation by its persisted prompt context, including conversations
    /// created before the catalog's titles were shortened.
    static func entry(matchingPromptContext context: String) -> TodayInHistoryEntry? {
        guard context.contains("<today in history>"),
              let descriptionStart = context.range(of: "<description>"),
              let descriptionEnd = context.range(
                of: "</description>",
                range: descriptionStart.upperBound..<context.endIndex
              ) else {
            return nil
        }
        let escapedDescription = String(context[descriptionStart.upperBound..<descriptionEnd.lowerBound])
        return byEscapedDescription[escapedDescription]
    }

    private static let byEscapedDescription: [String: TodayInHistoryEntry] = Dictionary(
        entries.map { ($0.description.xmlEscaped, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static let entries: [TodayInHistoryEntry] = [
        TodayInHistoryEntry(
            date: "01-01",
            title: "Haiti Declares Independence",
            description: "In 1804, Haiti became the first nation founded by a successful slave revolt, ending French colonial rule in Saint-Domingue.",
            relatedEntity: "Haitian Revolution"
        ),
        TodayInHistoryEntry(
            date: "01-10",
            title: "Caesar Crosses the Rubicon",
            description: "In 49 BC, Caesar led his army across the Rubicon into Italy, an irreversible act of civil war against the Roman Senate that gave rise to the phrase \"crossing the Rubicon.\"",
            relatedEntity: "Julius Caesar"
        ),
        TodayInHistoryEntry(
            date: "01-25",
            title: "St. Paul's Conversion",
            description: "The Church marks Paul's turn from persecutor of Christians to apostle on the road to Damascus, an event recounted in Acts as a sudden reversal of conviction.",
            relatedEntity: "Paul the Apostle"
        ),
        TodayInHistoryEntry(
            date: "01-26",
            title: "First Fleet Reaches Australia",
            description: "In 1788, British ships carrying convicts and settlers landed at Sydney Cove, founding the first European colony on the continent.",
            relatedEntity: "Colonial Australia"
        ),
        TodayInHistoryEntry(
            date: "01-27",
            title: "Auschwitz Liberated",
            description: "In 1945, the Red Army entered the Auschwitz-Birkenau camp complex, ending its use as a site of mass killing during the Holocaust.",
            relatedEntity: "The Holocaust"
        ),
        TodayInHistoryEntry(
            date: "02-11",
            title: "Nelson Mandela Freed",
            description: "In 1990, Mandela walked free after 27 years of imprisonment under apartheid, a turning point that led to South Africa's transition to democracy.",
            relatedEntity: "Nelson Mandela"
        ),
        TodayInHistoryEntry(
            date: "02-20",
            title: "John Glenn Orbits Earth",
            description: "In 1962, Glenn became the first American to orbit the Earth, circling the planet three times aboard Friendship 7.",
            relatedEntity: "John Glenn"
        ),
        TodayInHistoryEntry(
            date: "02-21",
            title: "Communist Manifesto Published",
            description: "Published in 1848, the pamphlet argued that history is driven by class struggle and called for the working class to overthrow capitalist society.",
            relatedEntity: "Karl Marx"
        ),
        TodayInHistoryEntry(
            date: "03-07",
            title: "Thomas Aquinas Dies",
            description: "Thomas Aquinas died in 1274 at the Cistercian abbey of Fossanova while traveling to the Second Council of Lyon, leaving the Summa Theologiae unfinished.",
            relatedEntity: "Thomas Aquinas"
        ),
        TodayInHistoryEntry(
            date: "03-09",
            title: "Wealth of Nations Published",
            description: "Published in 1776, Smith's account of markets, labor, and self-interest became the foundational text of modern economics.",
            relatedEntity: "Adam Smith"
        ),
        TodayInHistoryEntry(
            date: "03-12",
            title: "Gandhi's Salt March Begins",
            description: "In 1930, Gandhi set out on a 240-mile march to the sea to make salt in defiance of the British salt tax, a landmark act of nonviolent civil disobedience.",
            relatedEntity: "Mahatma Gandhi"
        ),
        TodayInHistoryEntry(
            date: "03-25",
            title: "Greek Independence Declared",
            description: "In 1821, the Greek War of Independence began, eventually ending nearly four centuries of Ottoman rule over the Greek peninsula.",
            relatedEntity: "Greek War of Independence"
        ),
        TodayInHistoryEntry(
            date: "03-26",
            title: "Bangladesh Declares Independence",
            description: "In 1971, Bangladesh declared independence from Pakistan, beginning a nine-month war that ended with the creation of a new nation.",
            relatedEntity: "Bangladesh Liberation War"
        ),
        TodayInHistoryEntry(
            date: "04-06",
            title: "U.S. Enters World War I",
            description: "In 1917, Congress declared war on Germany, formally bringing American forces into a conflict that had already reshaped Europe for three years.",
            relatedEntity: "World War I"
        ),
        TodayInHistoryEntry(
            date: "04-09",
            title: "Lee Surrenders at Appomattox",
            description: "In 1865, Confederate General Robert E. Lee surrendered to Union General Ulysses S. Grant, effectively ending the American Civil War.",
            relatedEntity: "American Civil War"
        ),
        TodayInHistoryEntry(
            date: "04-12",
            title: "Civil War Begins",
            description: "In 1861, Confederate forces opened fire on the Union garrison at Fort Sumter, South Carolina, starting the American Civil War.",
            relatedEntity: "American Civil War"
        ),
        TodayInHistoryEntry(
            date: "04-18",
            title: "Paul Revere's Ride",
            description: "On the night of April 18, 1775, Paul Revere rode to warn colonial militia of advancing British troops; fighting broke out the next morning, opening the American Revolutionary War.",
            relatedEntity: "American Revolutionary War"
        ),
        TodayInHistoryEntry(
            date: "04-25",
            title: "DNA Double Helix Published",
            description: "In 1953, their paper in Nature proposed the double-helix structure of DNA, drawing on X-ray data from Rosalind Franklin and reshaping modern biology.",
            relatedEntity: "DNA"
        ),
        TodayInHistoryEntry(
            date: "04-27",
            title: "South Africa's Democratic Election",
            description: "In 1994, South Africans of all races voted for the first time, an election that brought Nelson Mandela to the presidency and formally ended apartheid.",
            relatedEntity: "Nelson Mandela"
        ),
        TodayInHistoryEntry(
            date: "05-01",
            title: "Great Exhibition Opens",
            description: "In 1851, London hosted the first world's fair, showcasing industrial and scientific achievements from around the globe under a purpose-built glass hall.",
            relatedEntity: "The Great Exhibition"
        ),
        TodayInHistoryEntry(
            date: "05-06",
            title: "Eiffel Tower Opens",
            description: "Completed for the 1889 World's Fair in Paris, the tower opened to visitors on this date, though it had been open to workers since March of that year.",
            relatedEntity: "Eiffel Tower"
        ),
        TodayInHistoryEntry(
            date: "05-08",
            title: "Victory in Europe",
            description: "In 1945, Germany's unconditional surrender took effect, ending nearly six years of war on the European continent.",
            relatedEntity: "World War II"
        ),
        TodayInHistoryEntry(
            date: "05-10",
            title: "Transcontinental Railroad Completed",
            description: "In 1869, a golden spike was driven at Promontory Summit, Utah, joining the rail lines that connected the eastern and western United States.",
            relatedEntity: "Transcontinental Railroad"
        ),
        TodayInHistoryEntry(
            date: "05-11",
            title: "Didache Manuscript Copied",
            description: "The 1056 Constantinople manuscript that preserved the Didache's full text into the modern era, rediscovered by Philotheos Bryennios in 1873, was copied on this date, giving scholars their primary surviving witness to the text.",
            relatedEntity: "Didache"
        ),
        TodayInHistoryEntry(
            date: "05-14",
            title: "Israel Declares Independence",
            description: "In 1948, David Ben-Gurion proclaimed the establishment of the State of Israel as the British Mandate for Palestine expired.",
            relatedEntity: "State of Israel"
        ),
        TodayInHistoryEntry(
            date: "05-20",
            title: "Council of Nicaea Convenes",
            description: "In 325, bishops gathered at Nicaea at the summons of Constantine to settle the Arian controversy over the nature of Christ, producing the first form of the Nicene Creed.",
            relatedEntity: "Council of Nicaea"
        ),
        TodayInHistoryEntry(
            date: "05-29",
            title: "Constantinople Falls",
            description: "In 1453, Ottoman forces under Mehmed II captured Constantinople, ending the Byzantine Empire and marking a conventional boundary between the medieval and early modern periods.",
            relatedEntity: "Fall of Constantinople"
        ),
        TodayInHistoryEntry(
            date: "06-04",
            title: "Tiananmen Square Crackdown",
            description: "In 1989, the Chinese government used military force to end weeks of pro-democracy demonstrations centered on Tiananmen Square in Beijing.",
            relatedEntity: "Tiananmen Square protests"
        ),
        TodayInHistoryEntry(
            date: "06-05",
            title: "Marshall Plan Announced",
            description: "In 1947, U.S. Secretary of State George Marshall proposed a program of American economic aid to help rebuild Western Europe after World War II.",
            relatedEntity: "Marshall Plan"
        ),
        TodayInHistoryEntry(
            date: "06-06",
            title: "D-Day Landings",
            description: "In 1944, Allied troops landed on the beaches of Normandy, opening a new front in Western Europe against Nazi Germany.",
            relatedEntity: "D-Day"
        ),
        TodayInHistoryEntry(
            date: "06-08",
            title: "Discourse on the Method Published",
            description: "Published in 1637, Descartes's work introduced radical doubt as a method for arriving at certain knowledge, giving modern philosophy its \"I think, therefore I am.\"",
            relatedEntity: "René Descartes"
        ),
        TodayInHistoryEntry(
            date: "06-15",
            title: "Magna Carta Sealed",
            description: "In 1215, King John of England sealed the Magna Carta at Runnymede, establishing the principle that even the monarch was bound by law.",
            relatedEntity: "Magna Carta"
        ),
        TodayInHistoryEntry(
            date: "06-18",
            title: "Napoleon Defeated at Waterloo",
            description: "In 1815, a coalition led by Britain and Prussia defeated Napoleon Bonaparte near Waterloo, ending his final bid to rule France and Europe.",
            relatedEntity: "Napoleon Bonaparte"
        ),
        TodayInHistoryEntry(
            date: "06-19",
            title: "Council of Nicaea Concludes",
            description: "The council's business closed in 325 with the bishops' formal subscriptions to the creed condemning Arius's teaching that the Son was a created being.",
            relatedEntity: "Council of Nicaea"
        ),
        TodayInHistoryEntry(
            date: "06-22",
            title: "Galileo Recants",
            description: "In 1633, Galileo was compelled to renounce his support for a sun-centered solar system, a confrontation that became a lasting symbol of tension between science and authority.",
            relatedEntity: "Galileo Galilei"
        ),
        TodayInHistoryEntry(
            date: "06-28",
            title: "Treaty of Versailles Signed",
            description: "In 1919, the treaty formally ending World War I imposed harsh terms on Germany, consequences that later fed into the outbreak of World War II.",
            relatedEntity: "Treaty of Versailles"
        ),
        TodayInHistoryEntry(
            date: "06-30",
            title: "Einstein Submits Relativity Paper",
            description: "In 1905, Einstein submitted \"On the Electrodynamics of Moving Bodies,\" introducing special relativity and overturning the classical understanding of space and time.",
            relatedEntity: "Albert Einstein"
        ),
        TodayInHistoryEntry(
            date: "07-01",
            title: "Canada Becomes a Dominion",
            description: "In 1867, the British North America Act took effect, uniting several colonies into the Dominion of Canada.",
            relatedEntity: "Canada"
        ),
        TodayInHistoryEntry(
            date: "07-04",
            title: "Declaration of Independence Adopted",
            description: "In 1776, the Second Continental Congress adopted the Declaration of Independence, whose language on natural rights drew heavily on Enlightenment political philosophy.",
            relatedEntity: "Declaration of Independence"
        ),
        TodayInHistoryEntry(
            date: "07-05",
            title: "Newton's Principia Published",
            description: "In 1687, Newton's Philosophiæ Naturalis Principia Mathematica laid out the laws of motion and universal gravitation, unifying terrestrial and celestial physics.",
            relatedEntity: "Isaac Newton"
        ),
        TodayInHistoryEntry(
            date: "07-14",
            title: "Bastille Stormed",
            description: "In 1789, Parisians stormed the Bastille fortress, a flashpoint that opened the French Revolution and its upheaval of the old political and social order.",
            relatedEntity: "French Revolution"
        ),
        TodayInHistoryEntry(
            date: "07-16",
            title: "East-West Schism",
            description: "In 1054, mutual excommunications between papal legates and the Patriarch of Constantinople marked the formal, lasting split between the Western and Eastern churches.",
            relatedEntity: "East-West Schism"
        ),
        TodayInHistoryEntry(
            date: "08-04",
            title: "France Abolishes Feudal Privileges",
            description: "In the August Decrees of 1789, the Assembly swept away feudal dues, tithes, and noble privileges in a single overnight session during the French Revolution.",
            relatedEntity: "French Revolution"
        ),
        TodayInHistoryEntry(
            date: "08-06",
            title: "Hiroshima Bombed",
            description: "In 1945, the United States dropped an atomic bomb on Hiroshima, Japan, the first use of a nuclear weapon in warfare.",
            relatedEntity: "World War II"
        ),
        TodayInHistoryEntry(
            date: "08-15",
            title: "India Gains Independence",
            description: "In 1947, India became independent after nearly two centuries of British rule, coinciding with the partition that created Pakistan.",
            relatedEntity: "Indian independence movement"
        ),
        TodayInHistoryEntry(
            date: "08-18",
            title: "Women's Suffrage Ratified",
            description: "In 1920, the amendment prohibiting the denial of voting rights on account of sex was ratified, extending the franchise to women across the United States.",
            relatedEntity: "Women's suffrage"
        ),
        TodayInHistoryEntry(
            date: "08-24",
            title: "Vesuvius Eruption",
            description: "Mount Vesuvius's eruption in 79 AD buried Pompeii and Herculaneum in ash, preserving a detailed record of daily life in the Roman world; some scholarship suggests an autumn date instead.",
            relatedEntity: "Pompeii"
        ),
        TodayInHistoryEntry(
            date: "08-26",
            title: "Rights of Man Adopted",
            description: "In 1789, the National Constituent Assembly adopted a statement of universal rights that became a foundational document of the French Revolution.",
            relatedEntity: "French Revolution"
        ),
        TodayInHistoryEntry(
            date: "08-28",
            title: "I Have a Dream Speech",
            description: "In 1963, King addressed the March on Washington for Jobs and Freedom, calling for racial equality in one of the most quoted speeches in American history.",
            relatedEntity: "Martin Luther King Jr."
        ),
        TodayInHistoryEntry(
            date: "09-02",
            title: "Japan Formally Surrenders",
            description: "In 1945, Japanese officials signed the instrument of surrender aboard the USS Missouri, formally ending World War II.",
            relatedEntity: "World War II"
        ),
        TodayInHistoryEntry(
            date: "09-04",
            title: "Western Roman Empire Falls",
            description: "In 476, the Germanic general Odoacer deposed the last Western Roman emperor, Romulus Augustulus, an event later historians took as marking the empire's end.",
            relatedEntity: "Fall of the Roman Empire"
        ),
        TodayInHistoryEntry(
            date: "09-11",
            title: "September 11 Attacks",
            description: "In 2001, coordinated attacks on the World Trade Center and the Pentagon killed nearly 3,000 people and reshaped American foreign and domestic policy for decades.",
            relatedEntity: "September 11 attacks"
        ),
        TodayInHistoryEntry(
            date: "09-14",
            title: "Das Kapital Published",
            description: "Published in 1867, Marx's critique of political economy analyzed capitalism's internal contradictions and became the theoretical core of later socialist movements.",
            relatedEntity: "Karl Marx"
        ),
        TodayInHistoryEntry(
            date: "09-17",
            title: "U.S. Constitution Signed",
            description: "In 1787, delegates to the Constitutional Convention in Philadelphia signed the document establishing the federal framework of American government.",
            relatedEntity: "U.S. Constitution"
        ),
        TodayInHistoryEntry(
            date: "09-28",
            title: "Penicillin Discovered",
            description: "Alexander Fleming is traditionally credited with noticing, around this date in 1928, that a mold contaminating one of his cultures was killing surrounding bacteria -- the discovery that led to the first antibiotic.",
            relatedEntity: "Alexander Fleming"
        ),
        TodayInHistoryEntry(
            date: "10-04",
            title: "Sputnik 1 Launched",
            description: "In 1957, Sputnik 1 became the first artificial satellite to orbit the Earth, opening the Space Age and the Cold War space race.",
            relatedEntity: "Sputnik 1"
        ),
        TodayInHistoryEntry(
            date: "10-12",
            title: "Columbus Reaches the Americas",
            description: "In 1492, Christopher Columbus's expedition sighted land in the Bahamas, beginning sustained European contact with the Americas.",
            relatedEntity: "Christopher Columbus"
        ),
        TodayInHistoryEntry(
            date: "10-14",
            title: "Battle of Hastings",
            description: "In 1066, William of Normandy defeated King Harold II at Hastings, opening the Norman Conquest of England.",
            relatedEntity: "Battle of Hastings"
        ),
        TodayInHistoryEntry(
            date: "10-24",
            title: "United Nations Founded",
            description: "In 1945, the UN Charter entered into force after ratification by its founding members, formally establishing the United Nations.",
            relatedEntity: "United Nations"
        ),
        TodayInHistoryEntry(
            date: "10-29",
            title: "Wall Street Crash Begins",
            description: "Beginning on this day in 1929, a sharp collapse in U.S. stock prices set off the chain of events that led into the Great Depression.",
            relatedEntity: "Great Depression"
        ),
        TodayInHistoryEntry(
            date: "10-31",
            title: "Ninety-Five Theses Posted",
            description: "In 1517, Luther's disputation against the sale of indulgences, posted in Wittenberg, is traditionally dated to this day and is widely marked as the start of the Protestant Reformation.",
            relatedEntity: "Martin Luther"
        ),
        TodayInHistoryEntry(
            date: "11-07",
            title: "October Revolution Begins",
            description: "In 1917 (by the Gregorian calendar), Bolshevik forces seized power in Petrograd, leading to the founding of the Soviet state.",
            relatedEntity: "Russian Revolution"
        ),
        TodayInHistoryEntry(
            date: "11-09",
            title: "Berlin Wall Falls",
            description: "In 1989, East German authorities opened the border crossings, and crowds began tearing down the Berlin Wall, a symbolic end to the Cold War division of Europe.",
            relatedEntity: "Berlin Wall"
        ),
        TodayInHistoryEntry(
            date: "11-19",
            title: "Gettysburg Address Delivered",
            description: "In 1863, at the dedication of a military cemetery, Lincoln reframed the Civil War in a brief speech invoking the principle that all men are created equal.",
            relatedEntity: "Abraham Lincoln"
        ),
        TodayInHistoryEntry(
            date: "11-20",
            title: "Nuremberg Trials Begin",
            description: "In 1945, an international tribunal opened proceedings against senior Nazi officials, establishing precedents for prosecuting war crimes and crimes against humanity.",
            relatedEntity: "Nuremberg trials"
        ),
        TodayInHistoryEntry(
            date: "11-22",
            title: "President Kennedy Assassinated",
            description: "In 1963, President John F. Kennedy was shot and killed while riding in a motorcade in Dallas, Texas, a moment that shaped a generation's view of American public life.",
            relatedEntity: "John F. Kennedy"
        ),
        TodayInHistoryEntry(
            date: "11-24",
            title: "Origin of Species Published",
            description: "Published in 1859, Darwin's book set out the theory of evolution by natural selection, reshaping biology and the broader understanding of humanity's place in nature.",
            relatedEntity: "Charles Darwin"
        ),
        TodayInHistoryEntry(
            date: "12-01",
            title: "Rosa Parks Refuses to Move",
            description: "In 1955, Parks's refusal to give up her bus seat to a white passenger in Montgomery, Alabama, sparked a boycott that became a catalyst of the American civil rights movement.",
            relatedEntity: "Rosa Parks"
        ),
        TodayInHistoryEntry(
            date: "12-06",
            title: "13th Amendment Ratified",
            description: "In 1865, ratification of the 13th Amendment formally abolished slavery throughout the United States.",
            relatedEntity: "13th Amendment"
        ),
        TodayInHistoryEntry(
            date: "12-07",
            title: "Pearl Harbor Attacked",
            description: "In 1941, Japan launched a surprise attack on the U.S. naval base at Pearl Harbor, bringing the United States into World War II.",
            relatedEntity: "Pearl Harbor"
        ),
        TodayInHistoryEntry(
            date: "12-10",
            title: "Human Rights Declaration Adopted",
            description: "In 1948, the United Nations General Assembly adopted a declaration setting out rights held to belong to every person, drafted in the aftermath of World War II.",
            relatedEntity: "Universal Declaration of Human Rights"
        ),
        TodayInHistoryEntry(
            date: "12-15",
            title: "Bill of Rights Ratified",
            description: "In 1791, the first ten amendments to the U.S. Constitution were ratified, guaranteeing rights including speech, religion, and due process.",
            relatedEntity: "Bill of Rights"
        ),
        TodayInHistoryEntry(
            date: "12-16",
            title: "Boston Tea Party",
            description: "In 1773, colonists boarded British ships in Boston Harbor and destroyed a shipment of tea in protest of taxation without representation, escalating tensions toward the American Revolution.",
            relatedEntity: "American Revolutionary War"
        ),
        TodayInHistoryEntry(
            date: "12-17",
            title: "Wright Brothers' First Flight",
            description: "In 1903, Orville and Wilbur Wright achieved the first sustained, controlled flight of a powered aircraft at Kitty Hawk, North Carolina.",
            relatedEntity: "Wright Brothers"
        ),
        TodayInHistoryEntry(
            date: "12-25",
            title: "Charlemagne Crowned Emperor",
            description: "On Christmas Day in 800, Pope Leo III crowned Charlemagne emperor in Rome, an act later seen as founding the Holy Roman Empire and reviving the idea of an imperial office in the West.",
            relatedEntity: "Charlemagne"
        ),
    ]
}
