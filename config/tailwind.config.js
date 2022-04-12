const defaultTheme = require('tailwindcss/defaultTheme')

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
