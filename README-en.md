# GPS Track Logger — map features

These notes describe the terrain camera, direction-up tracking, speed colors, KMZ altitude, and the route from a map tap. The same steps are on the Help screen, in the language of the phone.

## 3D terrain and a tiltable camera

Apple Maps standard, satellite, and hybrid use realistic elevation. No API key is required. While a session is logging, the camera starts at about 52 degrees of pitch, inside the 45–60 degree range. Two fingers tilt the map, and that pitch is kept on the next follow, clamped between 0 and 65 degrees. Satellite and hybrid then read like a navigation app.

Tap the north dial to put the pitch back to 52 degrees and turn direction-up on again.

Keep whole track on screen stays a flat, north-up view so the whole line fits.

A downloaded OSM or Turistautak map can tilt and follow heading. It has no elevation mesh, so the ground stays flat. Hillshade still appears only when elevation files sit next to that map.

## Direction-up tracking

While logging, the camera heading follows the direction of travel, and the position arrow turns with it. At 1 m/s or faster the GPS course is the direction. Below that, the compass geographic heading is used. A weak compass keeps the last good direction instead of spinning the map. The arrow points up the screen when the camera is direction-up.

The north dial rotates so N still points north.

## Speed-colored track

Each stored point already has a speed. The line uses five colors, slow to fast: blue, teal, yellow, orange, carmine. The five dots on the map are that scale. The bands are fixed for the current usage, so a new maximum speed does not repaint the line already drawn:

- Run and hike: 1.0 / 1.6 / 2.2 / 3.0 m/s
- Bicycle: 3 / 6 / 8 / 11 m/s
- Car and motorbike: 8 / 14 / 22 / 33 m/s
- Aircraft: 25 / 50 / 75 / 100 m/s
- Watercraft: 2 / 5 / 8 / 12 m/s

A missing speed uses the slowest color. A saved track uses the same colors. Simplify only thins the drawn line; the kept points keep their speed. The stored route and the GPX or KMZ file still contain every accepted point.

## KMZ with real altitude

GPX already writes GPS altitude in `ele`. KMZ now does the visual half: when any point has a finite GPS altitude, the line and the Google Earth track use `altitudeMode` absolute and that altitude in the coordinate. A point without altitude is written as 0. Start, pause, and stop icons stay clamped to the ground.

If the track has no altitude at all, the line stays clamped to the ground.

Open the KMZ in Google Earth to see the line lifted off the terrain. This is the useful view for a flight or a mountain hike. Google Earth measures absolute altitude from the WGS84 ellipsoid. The phone stores altitude relative to sea level, so the line can sit a few tens of metres above or below the drawn terrain. The file is not converted.

Share from Saved tracks. The file lands in the Files app under On My iPhone → GPS Track Logger → Exports.

## Route to a tapped point

Tap the map, then Route. MapKit draws a walking, cycling, or driving path from your fix to that point. Hike and run use walking, bicycle uses cycling, and car and motorbike use driving. Aircraft and watercraft have no matching road mode, so the card offers Walk, Bicycle, and Car.

The request needs a network. It sends the two coordinates to Apple. The logged track is still stored only on the phone. Without a fix the card says No GPS. Without a path it says No route.

The path is a blue dashed line, separate from the speed-colored track and from the straight-line Distance tool. Tap the route chip to clear it. Starting another route cancels the request that is still running.
