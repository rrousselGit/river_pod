module.exports = {
  Sidebar: [
    "getting_started",
    
    {
      type: "category",
      label: "Concepts",
      items: [
        "concepts/providers",
        "concepts/reading",
        "concepts/provider_lifecycles",
        "concepts/combining_providers",
        "concepts/provider_observer",
        "concepts/why_immutability",
        "concepts/scopes",
        {
          type: "category",
          label: "Modifiers",
          items: [
            "concepts/modifiers/family",
            "concepts/modifiers/auto_dispose",
          ],
        },
      ],
    },
    {
      type: "category",
      label: "Guides",
      collapsed: false,
      items: [
        "cookbooks/testing",
        //"cookbooks/refresh",
      ],
    },
    {
      type: "category",
      label: "Official examples",
      items: [
        {
          type: "link",
          label: "Counter",
          href:
            "https://github.com/rrousselGit/river_pod/tree/master/examples/counter",
        },
        {
          type: "link",
          label: "Todo list",
          href:
            "https://github.com/rrousselGit/river_pod/tree/master/examples/todos",
        },
        {
          type: "link",
          label: "Marvel API",
          href:
            "https://github.com/rrousselGit/river_pod/tree/master/examples/marvel",
        },
      ],
    },
    {
      type: "category",
      label: "Third party examples",
      items: [
        {
          type: "link",
          label: "Android Launcher",
          href: "https://github.com/lohanidamodar/fl_live_launcher",
        },
        {
          type: "link",
          label: "Worldtime Clock",
          href: "https://github.com/lohanidamodar/flutter_worldtime",
        },
        {
          type: "link",
          label: "Dictionary App",
          href: "https://github.com/lohanidamodar/fl_dictio",
        },
        {
          type: "link",
          label: "Firebase Starter",
          href:
            "https://github.com/lohanidamodar/flutter_firebase_starter/tree/feature/riverpod",
        },
        {
          type: "link",
          label: "Time Tracking App (with Firebase)",
          href:
            "https://github.com/bizz84/starter_architecture_flutter_firebase",
        },
        {
          type: "link",
          label: "ListView paging with search",
          href: "https://github.com/tbm98/flutter_loadmore_search",
        },
        {
          type: "link",
          label: "Resocoder's Weather Bloc to Weather Riverpod",
          href: "https://github.com/campanagerald/flutter-bloc-library-v1-tutorial",
        },
        {
          type: "link",
          label: "Blood Pressure Tracker App",
          href: "https://github.com/UrosTodosijevic/blood_pressure_tracker",
        },
      ],
    },
    {
      type: "category",
      label: "Api references",
      collapsed: false,
      items: [
        {
          type: "link",
          label: "riverpod",
          href:
            "https://pub.dev/documentation/riverpod/latest/riverpod/riverpod-library.html",
        },
        {
          type: "link",
          label: "flutter_riverpod",
          href:
            "https://pub.dev/documentation//flutter_riverpod/latest/flutter_riverpod/flutter_riverpod-library.html",
        },
        {
          type: "link",
          label: "hooks_riverpod",
          href:
            "https://pub.dev/documentation/hooks_riverpod/latest/hooks_riverpod/hooks_riverpod-library.html",
        },
      ],
    },
  ],
};
