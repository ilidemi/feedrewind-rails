module.exports = {
    content: [
        './app/helpers/**/*.rb',
        './app/javascript/**/*.js',
        './app/views/**/*'
    ],
    theme: {
        screens: {
            '3xs': '340px',
            '2xs': '420px',
            'xs': '480px',
            'sm': '640px',
            'md': '768px',
            'lg': '1024px',
            'xl': '1280px',
            '2xl': '1536px',
        },
        extend: {
            colors: {
                primary: {
                    "50": "#f9f9fb",
                    "100": "#f4f4f8",
                    "200": "#e8e9ef",
                    "300": "#d4d6e2",
                    "400": "#a3a7c2",
                    "500": "#737aa2",
                    "600": "#595f86",
                    "700": "#4c5171",
                    "800": "#3c4059",
                    "900": "#313449"
                },
                red: {
                    "50": "#fef2f2",
                    "100": "#ffe3e4",
                    "200": "#feccce",
                    "300": "#fca4a9",
                    "400": "#fa717a",
                    "500": "#f24250",
                    "600": "#df2135",
                    "700": "#bc172a",
                    "800": "#9c1628",
                    "900": "#841828"
                }
            },
            spacing: {
                '0.25': '0.0625rem',
                '0.75': '0.1875rem'
            }
        }
    },
    plugins: [
        require('@tailwindcss/forms'),
        require('@tailwindcss/aspect-ratio'),
        require('@tailwindcss/typography'),
    ]
}
