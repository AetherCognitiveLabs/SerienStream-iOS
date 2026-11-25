import Foundation

/// Automatisierter End-to-End-Test der Scraping- und Resolver-Logik.
/// Läuft bei Launch-Arg `-smokeTest` und schreibt SMOKE-Zeilen ins DebugLog.
enum SmokeTest {
    static func runIfNeeded() {
        guard CommandLine.arguments.contains("-smokeTest") else { return }
        Task.detached {
            await run()
        }
    }

    static func run() async {
        let client = SerienStreamClient.shared
        DLog("SMOKE-START", category: "smoke")

        // 1. Endpoint-Probes
        for ep in SerienStreamClient.endpoints {
            let ok = await client.probe(ep.url)
            DLog("SMOKE probe \(ep.url): \(ok ? "PASS" : "FAIL")", category: "smoke")
        }

        // 2. Katalog
        do {
            let catalog = try await client.fetchCatalog()
            DLog("SMOKE catalog count=\(catalog.count): \(catalog.isEmpty ? "FAIL" : "PASS")", category: "smoke")
            if let first = catalog.first {
                DLog("SMOKE catalog first=\(first.slug) title=\(first.title)", category: "smoke")
            }
        } catch {
            DLog("SMOKE catalog FAIL: \(error.localizedDescription)", category: "smoke")
        }

        // 3. Beliebte Serien / Sektionen + Cover
        do {
            let sections = try await client.fetchPopularSections()
            DLog("SMOKE sections count=\(sections.count): \(sections.isEmpty ? "FAIL" : "PASS")", category: "smoke")
            for s in sections {
                let covers = s.series.filter { $0.coverURL != nil }.count
                DLog("SMOKE section '\(s.title)' series=\(s.series.count) covers=\(covers)", category: "smoke")
            }
            // Cover-Download testen
            if let cover = sections.first?.series.first?.coverURL {
                do {
                    let (data, resp) = try await URLSession.shared.data(from: cover)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    DLog("SMOKE cover download \(code) bytes=\(data.count): \(code == 200 && data.count > 1000 ? "PASS" : "FAIL")", category: "smoke")
                } catch {
                    DLog("SMOKE cover download FAIL: \(error.localizedDescription)", category: "smoke")
                }
            } else {
                DLog("SMOKE cover download FAIL: keine Cover-URL", category: "smoke")
            }
        } catch {
            DLog("SMOKE sections FAIL: \(error.localizedDescription)", category: "smoke")
        }

        // 4. Detail
        let testSlug = "und-dann-noch-paula"
        do {
            let detail = try await client.fetchDetail(slug: testSlug)
            var problems: [String] = []
            if detail.title == testSlug { problems.append("title") }
            if detail.coverURL == nil { problems.append("cover") }
            if detail.seasons.isEmpty { problems.append("seasons") }
            if detail.description.isEmpty { problems.append("description") }
            DLog("SMOKE detail: \(problems.isEmpty ? "PASS" : "FAIL missing=\(problems.joined(separator: ","))") seasons=\(detail.seasons) genres=\(detail.genres.count)", category: "smoke")
        } catch {
            DLog("SMOKE detail FAIL: \(error.localizedDescription)", category: "smoke")
        }

        // 5. Episoden
        do {
            let eps = try await client.fetchEpisodes(slug: testSlug, season: 1)
            DLog("SMOKE episodes count=\(eps.count): \(eps.isEmpty ? "FAIL" : "PASS")", category: "smoke")

            // 6. Hosterlinks
            if let ep = eps.first {
                do {
                    let links = try await client.fetchEpisodeLinks(ep)
                    DLog("SMOKE links count=\(links.count) providers=\(links.map { $0.providerName }.joined(separator: ",")): \(links.isEmpty ? "FAIL" : "PASS")", category: "smoke")
                } catch {
                    DLog("SMOKE links FAIL: \(error.localizedDescription)", category: "smoke")
                }
            }
        } catch {
            DLog("SMOKE episodes FAIL: \(error.localizedDescription)", category: "smoke")
        }

        DLog("SMOKE-END", category: "smoke")
    }
}
