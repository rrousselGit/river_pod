import React from 'react';
import useThemeContext from '@theme/hooks/useThemeContext'; //docs: https://v2.docusaurus.io/docs/2.0.0-alpha.69/theme-classic#usethemecontext

const ImageSwitcher = ({light, dark, alt}) => {
  const { isDarkTheme } = useThemeContext();

  return (
    <img src={isDarkTheme ? dark : light} alt={alt} />
  )
}

export default ImageSwitcher;