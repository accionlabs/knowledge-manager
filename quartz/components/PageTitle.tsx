import { pathToRoot } from "../util/path"
import { QuartzComponent, QuartzComponentConstructor, QuartzComponentProps } from "./types"
import { classNames } from "../util/lang"
import { i18n } from "../i18n"

const PageTitle: QuartzComponent = ({ fileData, cfg, displayClass }: QuartzComponentProps) => {
  const title = cfg?.pageTitle ?? i18n(cfg.locale).propertyDefaults.title
  const baseDir = pathToRoot(fileData.slug!)
  return (
    <h2 class={classNames(displayClass, "page-title")}>
      <a href={baseDir}>
        <img
          src={`${baseDir}/static/accionlabs-logo.png`}
          alt="Accion Labs"
          class="page-title-logo"
        />
        <span class="page-title-text">{title}</span>
      </a>
    </h2>
  )
}

PageTitle.css = `
.page-title {
  font-size: 1.25rem;
  margin: 0;
  font-family: var(--titleFont);
}

.page-title a {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 0.4rem;
  text-decoration: none;
  color: inherit;
}

.page-title-logo {
  max-width: 100%;
  height: auto;
  display: block;
}

.page-title-text {
  font-weight: 600;
}
`

export default (() => PageTitle) satisfies QuartzComponentConstructor
