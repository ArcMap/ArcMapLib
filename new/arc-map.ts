import { LitElement, html } from 'lit';
import { customElement } from 'lit/decorators.js';

import Map from '@arcgis/core/Map';
import MapView from '@arcgis/core/views/MapView';

@customElement('arc-map')
export class ArcMap extends LitElement {
  private _jsView: MapView | null = null;

  createRenderRoot() {
    return this;
  }

  render() {
    return html`
      <div id="mapDiv" style="width: 100%; height: 100%; min-height: 100vh;"></div>
      <slot></slot>
    `;
  }

  async firstUpdated(): Promise<void> {
    const map = new Map({
      basemap: 'streets-navigation-vector',
    });

    this._jsView = new MapView({
      container: this.querySelector('#mapDiv') as HTMLDivElement,
      map,
      center: [-84.39, 33.75],
      zoom: 10,
    });

    await this._jsView.when();
    console.log('[arc-map] view ready', this._jsView);
  }

  public async viewOnReady(): Promise<void> {
    let retries = 0;

    while (!this._jsView && retries < 100) {
      await new Promise((resolve) => setTimeout(resolve, 50));
      retries++;
    }

    if (!this._jsView) {
      throw new Error('[arc-map] _jsView was not created.');
    }

    await this._jsView.when();
  }

  public async getViewInstance(): Promise<MapView | null> {
    await this.viewOnReady();
    return this._jsView;
  }

  public enableInfoWindow(enable: boolean): void {
    if (!this._jsView) return;

    this._jsView.popupEnabled = enable;

    if (!enable) {
      this._jsView.closePopup();
    }
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'arc-map': ArcMap;
  }
}
