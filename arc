Old vs New Editor — Brief Summary
Old (Stencil + ArcGIS 3.x)
	•	2 separate widgets — Draw toolbar for creating, Edit toolbar for editing
	•	Each had its own separate events — rotate, scale, move, vertex were all different listeners
	•	Edited graphics directly on the display layer
	•	Simple boolean blockGeoJsonUpdate flag was enough
New (LitElement + ArcGIS 5.0)
	•	1 single widget — SketchViewModel handles everything
	•	All events flow through one update event — check state and toolEventInfo.type to know what happened
	•	Must clone graphic to sketchLayer first — SketchViewModel cannot edit FeatureLayer graphics directly
	•	Needed 6 new guard flags because LitElement lifecycle fires earlier than Stencil